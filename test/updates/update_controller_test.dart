import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khutati/core/settings/theme_mode_controller.dart';
import 'package:khutati/features/updates/application/update_controller.dart';
import 'package:khutati/features/updates/data/update_repository.dart';
import 'package:khutati/features/updates/domain/app_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Behaviour of the controller, which owns the two things the user can feel:
/// when a check is allowed to run, and what the UI is told when it fails.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UpdateManifest manifest(String version, {int code = 0}) => UpdateManifest(
    versionName: version,
    versionCode: code,
    apkUrl:
        'https://github.com/7sn-17/Khutati/releases/download/v$version/Khutati.apk',
  );

  late _ScriptedRepository repo;
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> setUpContainer([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    repo = _ScriptedRepository();
    container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        updateRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
  }

  UpdateController controller() =>
      container.read(updateControllerProvider.notifier);
  UpdateState state() => container.read(updateControllerProvider);

  int? lastCheck() => prefs.getInt(UpdateController.lastCheckKey);

  group('cooldown', () {
    test('a check younger than 60 minutes is skipped', () async {
      await setUpContainer(<String, Object>{
        UpdateController.lastCheckKey: DateTime.now()
            .subtract(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
      });
      repo.script.add(() async => const UpdateCheckResult());

      await controller().maybeCheck();

      expect(repo.calls, 0);
    });

    test('an expired cooldown runs the check', () async {
      await setUpContainer(<String, Object>{
        UpdateController.lastCheckKey: DateTime.now()
            .subtract(const Duration(minutes: 61))
            .millisecondsSinceEpoch,
      });
      repo.script.add(() async => const UpdateCheckResult());

      await controller().maybeCheck();

      expect(repo.calls, 1);
      expect(state().status, UpdateStatus.upToDate);
    });

    test('a manual check ignores the cooldown', () async {
      await setUpContainer(<String, Object>{
        UpdateController.lastCheckKey: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      });
      repo.script.add(() async => const UpdateCheckResult());

      await controller().check(force: true);

      expect(repo.calls, 1);
    });

    test('two quick background checks cost one request', () async {
      await setUpContainer();
      repo.script.add(() async => const UpdateCheckResult());

      await controller().maybeCheck();
      await controller().maybeCheck();

      expect(repo.calls, 1);
    });
  });

  group('honest failure', () {
    test(
      'a background failure stays silent and does not burn the cooldown',
      () async {
        await setUpContainer();
        repo.script.add(() async => throw const UpdateException('offline'));

        await controller().maybeCheck();

        expect(state().status, UpdateStatus.idle);
        expect(state().error, isNull);
        expect(lastCheck(), isNull);
      },
    );

    test(
      'a manual failure is reported and never looks like "up to date"',
      () async {
        await setUpContainer();
        repo.script.add(() async => throw const UpdateException('offline'));

        await controller().check(force: true);

        expect(state().status, UpdateStatus.failed);
        expect(state().error, isNotNull);
        expect(state().hasUpdate, isFalse);
        expect(lastCheck(), isNull);
      },
    );

    test('a failed refresh keeps a previously found update visible', () async {
      await setUpContainer();
      repo.script.add(
        () async => UpdateCheckResult(
          check: UpdateCheck(
            manifest: manifest('0.9.0', code: 40),
            source: UpdateSource.github,
          ),
        ),
      );
      await controller().check();

      repo.script.add(() async => throw const UpdateException('offline'));
      await controller().check(force: true);

      expect(state().status, UpdateStatus.failed);
      // The Settings panel keys the "view update" button off the manifest, so
      // a failed refresh must not discard it.
      expect(state().manifest?.versionName, '0.9.0');
    });
  });

  group('results', () {
    test('304 Not Modified is up to date and caches the ETag', () async {
      await setUpContainer();
      repo.script.add(
        () async => const UpdateCheckResult.notModified(etag: '"v1"'),
      );

      await controller().check(force: true);

      expect(state().status, UpdateStatus.upToDate);
      expect(state().error, isNull);
      expect(prefs.getString(UpdateController.etagKey), '"v1"');
      expect(lastCheck(), isNotNull);
    });

    test('the stored ETag is sent on the next check', () async {
      await setUpContainer(<String, Object>{
        UpdateController.etagKey: '"stored"',
      });
      repo.script.add(() async => const UpdateCheckResult());

      await controller().check(force: true);

      expect(repo.lastEtag, '"stored"');
    });

    test('a newer release becomes available and is remembered', () async {
      await setUpContainer();
      repo.script.add(
        () async => UpdateCheckResult(
          check: UpdateCheck(
            manifest: manifest('0.9.0', code: 40),
            source: UpdateSource.github,
          ),
        ),
      );

      await controller().check();

      expect(state().status, UpdateStatus.available);
      expect(state().manifest?.versionName, '0.9.0');
      expect(lastCheck(), isNotNull);
    });

    test('a skipped version is not offered again in the background', () async {
      await setUpContainer(<String, Object>{UpdateController.skippedKey: 40});
      repo.script.add(
        () async => UpdateCheckResult(
          check: UpdateCheck(
            manifest: manifest('0.9.0', code: 40),
            source: UpdateSource.github,
          ),
        ),
      );

      await controller().maybeCheck();

      expect(state().status, UpdateStatus.upToDate);
    });
  });
}

/// A repository whose every response is scripted by the test, so the controller
/// can be exercised without a socket.
class _ScriptedRepository extends UpdateRepository {
  _ScriptedRepository()
    : super(
        MockClient((http.Request _) async => http.Response('', 500)),
        supabaseUrl: '',
        supabaseAnonKey: '',
      );

  final List<Future<UpdateCheckResult> Function()> script =
      <Future<UpdateCheckResult> Function()>[];
  int calls = 0;
  String? lastEtag;

  @override
  Future<UpdateCheckResult> check({String? etag}) {
    calls++;
    lastEtag = etag;
    return script.removeAt(0)();
  }
}
