import 'package:drift/drift.dart';

import '../../domain/plan/step_progress.dart';
import '../database/app_database.dart';
import '../sync/sync_ids.dart';
import 'sync_queue_repository.dart';

/// User-owned progress. Never touches template tables, so a reset can always
/// restore the original plan (PRD section 5.5).
class UserStateRepository {
  UserStateRepository(this._db);

  final AppDatabase _db;

  Future<void> setStepCompleted(String stepId, StepProgress progress) async {
    final DateTime now = DateTime.now();
    final bool completed = progress == StepProgress.completed;
    final SyncQueueRepository queue = SyncQueueRepository(_db);

    await _db.transaction(() async {
      await _db
          .into(_db.userStepStates)
          .insertOnConflictUpdate(
            UserStepStatesCompanion.insert(
              stepId: stepId,
              completed: Value<bool>(completed),
              completedAt: Value<DateTime?>(completed ? now : null),
              // Store 1 for partialUp and 3 for partialDown. Keeping them
              // distinct is what makes the fourth tap reach 0% after a restart.
              progress: Value<int>(progress.code),
              updatedAt: Value<DateTime>(now),
            ),
          );
      await queue.enqueue('step_state', stepId, <String, Object?>{
        'step_id': stepId,
        'progress': progress.code,
        'completed': completed,
        'completed_at': isoOrNull(completed ? now : null),
        'updated_at': isoOrNull(now),
      });

      // A task marked complete counts every step as done without rewriting the
      // step rows. Once the user edits a step below 100%, that statement is no
      // longer true: reopen the task in the same transaction, or Today paints
      // the step back to complete on the next stream rebuild.
      if (completed) return;
      final StepRow? step = await (_db.select(
        _db.steps,
      )..where((Steps t) => t.id.equals(stepId))).getSingleOrNull();
      if (step == null) return;
      final UserTaskStateRow? task =
          await (_db.select(_db.userTaskStates)
                ..where((UserTaskStates t) => t.taskId.equals(step.taskId)))
              .getSingleOrNull();
      if (task == null || task.status != 'completed') return;

      await _db
          .into(_db.userTaskStates)
          .insertOnConflictUpdate(
            UserTaskStatesCompanion.insert(
              taskId: step.taskId,
              status: const Value<String>('in_progress'),
              completedAt: const Value<DateTime?>(null),
              updatedAt: now,
            ),
          );
      await queue.enqueue('task_state', step.taskId, <String, Object?>{
        'task_id': step.taskId,
        'status': 'in_progress',
        'completed_at': null,
        'updated_at': isoOrNull(now),
      });
    });
  }

  Future<Set<String>> completedStepIdsForDay(String dayId) async {
    final query = _db.select(_db.userStepStates).join(
      <Join<HasResultSet, dynamic>>[
        innerJoin(_db.steps, _db.steps.id.equalsExp(_db.userStepStates.stepId)),
        innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.steps.taskId)),
      ],
    );
    query.where(
      _db.tasks.dayId.equals(dayId) & _db.userStepStates.completed.equals(true),
    );

    final List<TypedResult> rows = await query.get();
    return <String>{
      for (final TypedResult row in rows)
        row.readTable(_db.userStepStates).stepId,
    };
  }

  Future<StepProgress> stepProgress(String stepId) async {
    final List<UserStepStateRow> rows = await (_db.select(
      _db.userStepStates,
    )..where((t) => t.stepId.equals(stepId))).get();
    if (rows.isEmpty) return StepProgress.notStarted;
    return _progressOf(rows.first);
  }

  /// Rows written before the two-tap column existed only carry `completed`.
  /// They are treated as fully done, so upgrading never downgrades progress.
  static StepProgress _progressOf(UserStepStateRow row) {
    final StepProgress progress = StepProgress.tryParse(row.progress);
    if (progress == StepProgress.notStarted && row.completed) {
      return StepProgress.completed;
    }
    return progress;
  }

  /// Explicit task statuses for one day, keyed by task id. Today maps these to
  /// the domain status so a task completed as a whole is not reopened just
  /// because its individual step rows are still unchecked.
  Future<Map<String, String>> taskStatusesForDay(String dayId) async {
    final query = _db.select(_db.userTaskStates).join(
      <Join<HasResultSet, dynamic>>[
        innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.userTaskStates.taskId)),
      ],
    );
    query.where(_db.tasks.dayId.equals(dayId));

    final List<TypedResult> rows = await query.get();
    return <String, String>{
      for (final TypedResult row in rows)
        row.readTable(_db.userTaskStates).taskId: row
            .readTable(_db.userTaskStates)
            .status,
    };
  }

  /// Stored step states for one day, keyed by step id. Today and Plan both
  /// read this so a two-tap partial step shows the same fraction everywhere.
  Future<Map<String, StepProgress>> stepProgressForDay(String dayId) async {
    final query = _db.select(_db.userStepStates).join(
      <Join<HasResultSet, dynamic>>[
        innerJoin(_db.steps, _db.steps.id.equalsExp(_db.userStepStates.stepId)),
        innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.steps.taskId)),
      ],
    );
    query.where(_db.tasks.dayId.equals(dayId));

    final List<TypedResult> rows = await query.get();
    return <String, StepProgress>{
      for (final TypedResult row in rows)
        row.readTable(_db.userStepStates).stepId: _progressOf(
          row.readTable(_db.userStepStates),
        ),
    };
  }

  /// Every stored step state, for read models that render the whole plan at
  /// once (the Plan tab).
  Future<Map<String, StepProgress>> allStepProgresses() async {
    final List<UserStepStateRow> rows = await _db
        .select(_db.userStepStates)
        .get();
    return <String, StepProgress>{
      for (final UserStepStateRow row in rows) row.stepId: _progressOf(row),
    };
  }

  /// All completed step ids, for read models that render the whole plan at
  /// once (the Plan tab). Today scopes this per day instead.
  Future<Set<String>> allCompletedStepIds() async {
    final List<UserStepStateRow> rows = await (_db.select(
      _db.userStepStates,
    )..where((t) => t.completed.equals(true))).get();
    return <String>{for (final UserStepStateRow row in rows) row.stepId};
  }

  /// Explicit task statuses for the whole plan, keyed by task id.
  Future<Map<String, String>> allTaskStatuses() async {
    final List<UserTaskStateRow> rows = await _db
        .select(_db.userTaskStates)
        .get();
    return <String, String>{
      for (final UserTaskStateRow row in rows) row.taskId: row.status,
    };
  }

  Future<void> setTaskStatus(
    String taskId,
    String status, {
    DateTime? at,
  }) async {
    final DateTime now = at ?? DateTime.now();
    await _db
        .into(_db.userTaskStates)
        .insertOnConflictUpdate(
          UserTaskStatesCompanion.insert(
            taskId: taskId,
            status: Value<String>(status),
            completedAt: Value<DateTime?>(status == 'completed' ? now : null),
            updatedAt: now,
          ),
        );
    await SyncQueueRepository(_db)
        .enqueue('task_state', taskId, <String, Object?>{
          'task_id': taskId,
          'status': status,
          'completed_at': isoOrNull(status == 'completed' ? now : null),
          'updated_at': isoOrNull(now),
        });
  }

  Future<void> addNote(String taskId, String body) {
    return _db
        .into(_db.notes)
        .insert(
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
      await (_db.delete(
        _db.reviewFlags,
      )..where((t) => t.taskId.equals(taskId))).go();
      return;
    }
    await _db
        .into(_db.reviewFlags)
        .insertOnConflictUpdate(
          ReviewFlagsCompanion.insert(
            taskId: taskId,
            flaggedAt: DateTime.now(),
          ),
        );
  }
}
