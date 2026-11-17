import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// User-owned progress. Never touches template tables, so a reset can always
/// restore the original plan (PRD section 5.5).
class UserStateRepository {
  UserStateRepository(this._db);

  final AppDatabase _db;

  Future<void> setStepCompleted(String stepId, bool completed, {DateTime? at}) {
    final DateTime now = at ?? DateTime.now();
    return _db.into(_db.userStepStates).insertOnConflictUpdate(
          UserStepStatesCompanion.insert(
            stepId: stepId,
            completed: Value<bool>(completed),
            completedAt: Value<DateTime?>(completed ? now : null),
          ),
        );
  }

  Future<Set<String>> completedStepIdsForDay(String dayId) async {
    final query = _db.select(_db.userStepStates).join(<Join<HasResultSet, dynamic>>[
      innerJoin(_db.steps, _db.steps.id.equalsExp(_db.userStepStates.stepId)),
      innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.steps.taskId)),
    ]);
    query.where(
      _db.tasks.dayId.equals(dayId) & _db.userStepStates.completed.equals(true),
    );

    final List<TypedResult> rows = await query.get();
    return <String>{
      for (final TypedResult row in rows) row.readTable(_db.userStepStates).stepId,
    };
  }

  Future<void> setTaskStatus(String taskId, String status, {DateTime? at}) {
    final DateTime now = at ?? DateTime.now();
    return _db.into(_db.userTaskStates).insertOnConflictUpdate(
          UserTaskStatesCompanion.insert(
            taskId: taskId,
            status: Value<String>(status),
            completedAt: Value<DateTime?>(status == 'completed' ? now : null),
            updatedAt: now,
          ),
        );
  }

  Future<void> addNote(String taskId, String body) {
    return _db.into(_db.notes).insert(
          NotesCompanion.insert(
            taskId: taskId,
            body: body,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<List<NoteRow>> notesFor(String taskId) {
    return (_db.select(_db.notes)..where((t) => t.taskId.equals(taskId))).get();
  }

  Future<void> setReviewFlag(String taskId, bool flagged) async {
    if (!flagged) {
      await (_db.delete(_db.reviewFlags)..where((t) => t.taskId.equals(taskId))).go();
      return;
    }
    await _db.into(_db.reviewFlags).insertOnConflictUpdate(
          ReviewFlagsCompanion.insert(taskId: taskId, flaggedAt: DateTime.now()),
        );
  }
}
