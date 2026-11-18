import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khutati/features/updates/data/update_repository.dart';
import 'package:khutati/features/updates/domain/app_release.dart';

/// The update checker is the one place the app talks to a third party with a
/// quota. These tests pin the three properties that keep it inside GitHub's
/// 60-requests-per-hour anonymous limit:
///
/// * a conditional request sends the stored ETag and treats `304` as success;
/// * a `403` API failure falls back to the static Atom feed;
/// * only a total failure throws, so the UI can stay honest about it.
void main() {
  const String releaseBody = '''
[
  {
    "tag_name": "v0.9.0",
    "html_url": "https://github.com/7sn-17/Khutati/releases/tag/v0.9.0",
    "body": "ملاحظات الإصدار",
    "published_at": "2026-12-01T10:00:00Z",
    "draft": false,
    "assets": [
      {
        "name": "Khutati.apk",
        "browser_download_url": "https://github.com/7sn-17/Khutati/releases/download/v0.9.0/Khutati.apk"
      }
    ]
  }
]
''';

  const String atomBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Release notes from Khutati</title>
  <entry>
    <id>tag:github.com,2008:Repository/1/v0.9.0</id>
    <updated>2026-12-01T10:00:00Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/7sn-17/Khutati/releases/tag/v0.9.0"/>
    <title>v0.9.0</title>
  </entry>
  <entry>
    <id>tag:github.com,2008:Repository/1/v0.8.2</id>
    <updated>2026-11-18T20:00:00Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/7sn-17/Khutati/releases/tag/v0.8.2"/>
    <title>v0.8.2</title>
  </entry>
</feed>
''';

  UpdateRepository repository(MockClient client) =>
      UpdateRepository(client, supabaseUrl: '', supabaseAnonKey: '');

  test('sends If-None-Match and treats 304 as a successful check', () async {
    int calls = 0;
    final List<String?> sentEtags = <String?>[];

    final MockClient client = MockClient((http.Request request) async {
      calls++;
      sentEtags.add(request.headers['If-None-Match']);
      if (calls == 1) {
        return http.Response(
          releaseBody,
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'etag': '"release-list-v1"',
          },
        );
      }
      return http.Response('', 304, headers: <String, String>{});
    });

    final UpdateRepository repo = repository(client);

    final UpdateCheckResult first = await repo.check();
    expect(first.hasRelease, isTrue);
    expect(first.etag, '"release-list-v1"');
    expect(sentEtags.single, isNull);

    final UpdateCheckResult second = await repo.check(etag: first.etag);
    expect(sentEtags.last, '"release-list-v1"');
    expect(second.notModified, isTrue);
    expect(second.hasRelease, isFalse);
    expect(calls, 2);
  });

  test('falls back to the Atom feed when the API is rate limited', () async {
    final List<String> hosts = <String>[];

    final MockClient client = MockClient((http.Request request) async {
      hosts.add(request.url.toString());
      if (request.url.host == 'api.github.com') {
        return http.Response(
          '{"message":"API rate limit exceeded"}',
          403,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('releases.atom')) {
        return http.Response(
          atomBody,
          200,
          headers: <String, String>{'content-type': 'application/atom+xml'},
        );
      }
      return http.Response('not found', 404);
    });

    final UpdateCheckResult result = await repository(client).check();

    expect(result.hasRelease, isTrue);
    final UpdateManifest manifest = result.check!.manifest;
    expect(manifest.versionName, '0.9.0');
    expect(manifest.versionCode, 0);
    // The tag keeps its `v`: GitHub asset URLs are built from the pushed tag.
    expect(
      manifest.apkUrl,
      'https://github.com/7sn-17/Khutati/releases/download/v0.9.0/Khutati.apk',
    );
    expect(manifest.pageUrl, contains('/releases/tag/v0.9.0'));
    expect(hosts, hasLength(2));
  });

  test('an empty release list is a success, not a failure', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response(
        '[]',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      ),
    );

    final UpdateCheckResult result = await repository(client).check();

    expect(result.hasRelease, isFalse);
    expect(result.notModified, isFalse);
  });

  test('throws only when the API and the Atom feed both fail', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response('boom', 500),
    );

    await expectLater(
      repository(client).check(),
      throwsA(isA<UpdateException>()),
    );
  });

  test('a timeout is a failure, not an empty result', () async {
    final MockClient client = MockClient((http.Request request) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return http.Response(releaseBody, 200);
    });

    final UpdateRepository repo = UpdateRepository(
      client,
      supabaseUrl: '',
      supabaseAnonKey: '',
      timeout: const Duration(milliseconds: 40),
    );

    await expectLater(repo.check(), throwsA(isA<UpdateException>()));
  });

  test('decodes Arabic notes as UTF-8', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response.bytes(
        utf8.encode(releaseBody),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final UpdateCheckResult result = await repository(client).check();

    expect(result.check!.manifest.notes, 'ملاحظات الإصدار');
  });
}
