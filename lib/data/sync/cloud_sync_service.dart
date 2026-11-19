import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../providers.dart';
import '../repositories/schedule_repository.dart';
import '../repositories/sync_queue_repository.dart';
import '../../domain/plan/practical_weekdays.dart';
import '../../domain/plan/schedule_engine.dart' show ScheduleOverrideInput;

/// Offline-first uploader for user progress and focus history.
///
/// The app never waits for the network to save progress: SQLite is written
/// first, and [SyncQueueRepository] holds the pending snapshot. This service
/// drains that outbox every five minutes and whenever the app is paused. A
/// manual resume/sign-in also pulls remote rows so reinstalling on a new phone
/// restores the account.
class CloudSyncService {
  CloudSyncService(this._ref);

  static const Duration interval = Duration(minutes: 5);
  static const Duration pullInterval = Duration(minutes: 10);

  final Ref _ref;
  Timer? _timer;
  bool _flushing = false;
  DateTime? _lastPull;

  void start() {
    _timer ??= Timer.periodic(interval, (Timer _) {
      unawaited(syncNow(pull: false));
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Pushes queued snapshots, then optionally pulls remote state.
  /// Returns `true` when every queued row uploaded.
  Future<bool> syncNow({bool pull = true}) async {
    if (_flushing) return false;
    _flushing = true;
    try {
      final SupabaseClient client;
      try {
        client = Supabase.instance.client;
      } catch (_) {
        return false; // Supabase is not configured in this build.
      }
      final User? user = client.auth.currentUser;
      if (user == null) return false;

      final AppDatabase db = _ref.read(appDatabaseProvider);
      final SyncQueueRepository queue = SyncQueueRepository(db);
      final List<SyncQueueRow> rows = await queue.pending();
      final bool pushed = await _push(client, user, queue, rows);

      final DateTime now = DateTime.now();
      final bool pullDue =
          _lastPull == null || now.difference(_lastPull!) >= pullInterval;
      if (pull && pullDue) {
        await _pull(client, user, db);
        _lastPull = now;
      }
      return pushed;
    } catch (_) {
      // Locked database, expired token, no network: keep the outbox intact and
      // retry on the next five-minute tick or the next resume.
      return false;
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _push(
    SupabaseClient client,
    User user,
    SyncQueueRepository queue,
    List<SyncQueueRow> rows,
  ) async {
    if (rows.isEmpty) return true;

    final Map<String, List<SyncQueueRow>> grouped =
        <String, List<SyncQueueRow>>{};
    for (final SyncQueueRow row in rows) {
      grouped.putIfAbsent(row.entity, () => <SyncQueueRow>[]).add(row);
    }

    final List<int> succeeded = <int>[];
    final List<int> failed = <int>[];

    for (final MapEntry<String, List<SyncQueueRow>> group in grouped.entries) {
      final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
      for (final SyncQueueRow row in group.value) {
        final Object? decoded = jsonDecode(row.payload);
        if (decoded is! Map) continue;
        payload.add(<String, dynamic>{
          ...decoded.cast<String, dynamic>(),
          'user_id': user.id,
        });
      }
      if (payload.isEmpty) {
        failed.addAll(group.value.map((SyncQueueRow r) => r.id));
        continue;
      }

      try {
        switch (group.key) {
          case 'task_state':
            await client
                .from('user_task_states')
                .upsert(payload, onConflict: 'user_id,task_id');
            break;
          case 'step_state':
            await client
                .from('user_step_states')
                .upsert(payload, onConflict: 'user_id,step_id');
            break;
          case 'focus_session':
            await client
                .from('focus_sessions')
                .upsert(payload, onConflict: 'user_id,id');
            break;
          case 'schedule_settings':
            await client
                .from('user_schedule_settings')
                .upsert(payload, onConflict: 'user_id');
            break;
          case 'schedule_override':
            await client
                .from('user_schedule_overrides')
                .upsert(payload, onConflict: 'user_id,task_id');
            break;
          default:
            // An unknown entity can never succeed; dropping it prevents a
            // permanently stuck queue after a downgrade.
            break;
        }
        succeeded.addAll(group.value.map((SyncQueueRow r) => r.id));
      } catch (_) {
        failed.addAll(group.value.map((SyncQueueRow r) => r.id));
      }
    }

    // Remove only confirmed rows. A partial outage must never lose the rows
    // that failed, so the next tick retries them.
    await queue.removeIds(succeeded);
    await queue.recordFailure(failed);
    return failed.isEmpty;
  }

  Future<void> _pull(SupabaseClient client, User user, AppDatabase db) async {
    await _pullTaskStates(client, user, db);
    await _pullStepStates(client, user, db);
    await _pullFocusSessions(client, user, db);
    await _pullScheduleSettings(client, user);
    await _pullScheduleOverrides(client, user);
  }

  /// Pulls manual task placements. A soft-deleted row clears the local
  /// override, so removing a move on one device also removes it everywhere.
  Future<void> _pullScheduleOverrides(SupabaseClient client, User user) async {
    final List<dynamic> raw = await client
        .from('user_schedule_overrides')
        .select()
        .eq('user_id', user.id);
    final ScheduleRepository schedule = _ref.read(scheduleRepositoryProvider);
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> row = item.cast<String, dynamic>();
      final String? taskId = row['task_id'] as String?;
      final DateTime? remoteAt = DateTime.tryParse(
        (row['updated_at'] as String?) ?? '',
      );
      if (taskId == null || remoteAt == null) continue;

      if (row['deleted'] == true) {
        await schedule.applyRemoteOverride(taskId, null, remoteAt);
        continue;
      }
      final dynamic day = row['day_number'];
      if (day is! num) continue;
      final dynamic position = row['position'];
      final String? startClock = row['start_clock'] as String?;
      await schedule.applyRemoteOverride(
        taskId,
        ScheduleOverrideInput(
          dayNumber: day.toInt(),
          position: position is num ? position.toInt() : null,
          startClock: startClock,
        ),
        remoteAt,
      );
    }
  }

  /// Pulls the cross-device practical-weekday choice. The local setting wins on
  /// ties, exactly like progress; an empty remote array means the original
  /// schedule and therefore clears any local override.
  Future<void> _pullScheduleSettings(SupabaseClient client, User user) async {
    final List<dynamic> raw = await client
        .from('user_schedule_settings')
        .select()
        .eq('user_id', user.id)
        .limit(1);
    if (raw.isEmpty) return;
    final dynamic item = raw.first;
    if (item is! Map) return;
    final Map<String, dynamic> row = item.cast<String, dynamic>();
    final DateTime? remoteAt = DateTime.tryParse(
      (row['updated_at'] as String?) ?? '',
    );
    if (remoteAt == null) return;

    final dynamic remoteDays = row['practical_weekdays'];
    List<int>? weekdays;
    if (remoteDays is List) {
      final List<int> values = <int>[
        for (final dynamic value in remoteDays)
          if (value is num) value.toInt(),
      ];
      if (values.length != remoteDays.length) return;
      if (values.isNotEmpty) {
        try {
          weekdays = PracticalWeekdays.validate(values);
        } catch (_) {
          // A malformed remote preference must not corrupt the local plan.
          return;
        }
      }
    }

    await _ref.read(scheduleRepositoryProvider).applyRemote(weekdays, remoteAt);
  }

  Future<void> _pullTaskStates(
    SupabaseClient client,
    User user,
    AppDatabase db,
  ) async {
    final List<dynamic> raw = await client
        .from('user_task_states')
        .select()
        .eq('user_id', user.id);
    final List<UserTaskStateRow> local = await db
        .select(db.userTaskStates)
        .get();
    final Map<String, UserTaskStateRow> byId = <String, UserTaskStateRow>{
      for (final UserTaskStateRow row in local) row.taskId: row,
    };

    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> row = item.cast<String, dynamic>();
      final String? taskId = row['task_id'] as String?;
      if (taskId == null || taskId.isEmpty) continue;
      final DateTime? remoteAt = DateTime.tryParse(
        (row['updated_at'] as String?) ?? '',
      );
      final UserTaskStateRow? current = byId[taskId];
      if (current != null &&
          remoteAt != null &&
          !remoteAt.toUtc().isAfter(current.updatedAt.toUtc())) {
        continue;
      }
      await db
          .into(db.userTaskStates)
          .insertOnConflictUpdate(
            UserTaskStatesCompanion.insert(
              taskId: taskId,
              status: Value<String>(
                (row['status'] as String?) ?? 'not_started',
              ),
              completedAt: Value<DateTime?>(
                DateTime.tryParse((row['completed_at'] as String?) ?? ''),
              ),
              updatedAt: remoteAt ?? DateTime.now(),
            ),
          );
    }
  }

  Future<void> _pullStepStates(
    SupabaseClient client,
    User user,
    AppDatabase db,
  ) async {
    final List<dynamic> raw = await client
        .from('user_step_states')
        .select()
        .eq('user_id', user.id);
    final List<UserStepStateRow> local = await db
        .select(db.userStepStates)
        .get();
    final Map<String, UserStepStateRow> byId = <String, UserStepStateRow>{
      for (final UserStepStateRow row in local) row.stepId: row,
    };

    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> row = item.cast<String, dynamic>();
      final String? stepId = row['step_id'] as String?;
      if (stepId == null || stepId.isEmpty) continue;
      final DateTime? remoteAt = DateTime.tryParse(
        (row['updated_at'] as String?) ?? '',
      );
      final UserStepStateRow? current = byId[stepId];
      final DateTime? localAt = current?.updatedAt;
      if (current != null &&
          remoteAt != null &&
          localAt != null &&
          !remoteAt.toUtc().isAfter(localAt.toUtc())) {
        continue;
      }
      final int progress = (row['progress'] as num?)?.toInt() ?? 0;
      await db
          .into(db.userStepStates)
          .insertOnConflictUpdate(
            UserStepStatesCompanion.insert(
              stepId: stepId,
              completed: Value<bool>(row['completed'] == true),
              completedAt: Value<DateTime?>(
                DateTime.tryParse((row['completed_at'] as String?) ?? ''),
              ),
              progress: Value<int>(progress),
              updatedAt: Value<DateTime?>(remoteAt ?? DateTime.now()),
            ),
          );
    }
  }

  Future<void> _pullFocusSessions(
    SupabaseClient client,
    User user,
    AppDatabase db,
  ) async {
    final List<dynamic> raw = await client
        .from('focus_sessions')
        .select()
        .eq('user_id', user.id);
    final List<FocusSession> local = await db.select(db.focusSessions).get();
    final Set<String> known = <String>{
      for (final FocusSession row in local)
        if (row.clientId != null) row.clientId!,
    };

    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> row = item.cast<String, dynamic>();
      final String? clientId = row['id'] as String?;
      if (clientId == null || clientId.isEmpty || known.contains(clientId)) {
        continue;
      }
      final DateTime? startedAt = DateTime.tryParse(
        (row['started_at'] as String?) ?? '',
      );
      if (startedAt == null) continue;
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              clientId: Value<String?>(clientId),
              taskId: Value<String?>(row['task_id'] as String?),
              taskTitle: Value<String?>(row['task_title'] as String?),
              mode: Value<String>((row['mode'] as String?) ?? 'pomodoro'),
              stepId: Value<String?>(row['step_id'] as String?),
              phase: (row['phase'] as String?) ?? 'focus',
              plannedSeconds: (row['planned_seconds'] as num?)?.toInt() ?? 0,
              actualSeconds: (row['actual_seconds'] as num?)?.toInt() ?? 0,
              startedAt: startedAt,
              endedAt: Value<DateTime?>(
                DateTime.tryParse((row['ended_at'] as String?) ?? ''),
              ),
              completed: Value<bool>(row['completed'] == true),
            ),
          );
    }
  }
}

final Provider<CloudSyncService> cloudSyncServiceProvider =
    Provider<CloudSyncService>((Ref ref) {
      final CloudSyncService service = CloudSyncService(ref)..start();
      ref.onDispose(service.dispose);
      return service;
    });
