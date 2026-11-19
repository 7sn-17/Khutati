import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database — the single source of truth (PRD section 6.1).
///
/// Template tables hold the imported plan and are only written by the import
/// pipeline. User tables hold progress, overrides, additions, sessions, notes
/// and settings. Keeping them apart is what makes "restore to default" safe.
@DriftDatabase(
  tables: [
    Plans,
    Subjects,
    Chapters,
    Lessons,
    Days,
    Tasks,
    Steps,
    Breaks,
    UserTaskStates,
    UserStepStates,
    UserOverrides,
    ScheduleOverrides,
    UserAdditions,
    FocusSessions,
    Notes,
    ReviewFlags,
    AppSettings,
    SyncQueue,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Used by tests and by any tooling that needs an isolated database.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // Query paths used by Today and Plan; added explicitly so the intent
          // is visible and index names stay stable across drift upgrades.
          await customStatement('CREATE INDEX IF NOT EXISTS idx_days_day_number ON days(day_number)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_day ON tasks(day_id)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_subject ON tasks(subject_id)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_steps_task ON steps(task_id)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_breaks_day ON breaks(day_id)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_sessions_started ON focus_sessions(started_at)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_overrides_target ON user_overrides(target_type, target_id)');
          await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_focus_client_id ON focus_sessions(client_id) WHERE client_id IS NOT NULL');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_queue_entity ON sync_queue(entity, entity_id)');
          await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_override_task ON schedule_overrides(task_id)');
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // v2 adds the two-tap step state. Existing rows keep `completed`
          // and are read as fully done until the user taps again.
          if (from < 2) {
            await m.addColumn(userStepStates, userStepStates.progress);
          }
          // v3 adds mode + taskTitle to focus sessions for the history view.
          if (from < 3) {
            await m.addColumn(focusSessions, focusSessions.mode);
            await m.addColumn(focusSessions, focusSessions.taskTitle);
          }
          // v4 adds the offline-first sync outbox, a stable cloud id for
          // focus sessions, and a local timestamp for step-state conflict
          // resolution. Existing step rows keep their exact progress code
          // (including code 3 = partialDown), so the 4-tap cycle survives.
          if (from < 4) {
            await m.addColumn(userStepStates, userStepStates.updatedAt);
            await m.addColumn(focusSessions, focusSessions.clientId);
            await m.createTable(syncQueue);
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_focus_client_id '
              'ON focus_sessions(client_id) WHERE client_id IS NOT NULL',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_sync_queue_entity '
              'ON sync_queue(entity, entity_id)',
            );
          }
          // v5 adds manual schedule overrides. Existing installs keep their
          // schedule untouched; an empty table means "fully automatic".
          if (from < 5) {
            await m.createTable(scheduleOverrides);
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_override_task '
              'ON schedule_overrides(task_id)',
            );
          }
        },
        beforeOpen: (details) async {
          // Referential integrity is required for the template/user split to
          // mean anything; SQLite leaves it off by default.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
