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
  tables: <Type>[
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
    UserAdditions,
    FocusSessions,
    Notes,
    ReviewFlags,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Used by tests and by any tooling that needs an isolated database.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

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
        },
        beforeOpen: (details) async {
          // Referential integrity is required for the template/user split to
          // mean anything; SQLite leaves it off by default.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
