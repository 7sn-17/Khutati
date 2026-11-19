import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/providers.dart';
import '../domain/focus_log.dart';

/// Everything the focus log needs, already normalised and sorted newest first.
class FocusLogData {
  const FocusLogData(this.entries);

  final List<FocusLogEntry> entries;

  List<FocusLogEntry> filtered(
    FocusLogRange range, {
    required DateTime now,
    String? mode,
  }) {
    return FocusLog.filter(entries, range, now: now, mode: mode);
  }

  FocusLogStats stats(FocusLogRange range, {required DateTime now}) {
    return FocusLog.stats(filtered(range, now: now), now: now);
  }

  List<FocusLogDay> days(FocusLogRange range, {required DateTime now}) {
    return FocusLog.group(filtered(range, now: now));
  }

  List<FocusLogDay> activity({required DateTime now, int days = 14}) {
    return FocusLog.activity(entries, now: now, days: days);
  }
}

/// Live focus log. Break phases are kept because they explain the gaps
/// between sessions; every focus statistic ignores them.
final StreamProvider<FocusLogData> focusLogProvider =
    StreamProvider<FocusLogData>((Ref ref) {
      final AppDatabase db = ref.watch(appDatabaseProvider);
      final query = db.select(db.focusSessions)
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
      return query.watch().map(_toData);
    });

FocusLogData _toData(List<FocusSession> rows) {
  return FocusLogData(<FocusLogEntry>[
    for (final FocusSession row in rows)
      FocusLogEntry(
        id: row.clientId ?? 'local-${row.id}',
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        mode: row.mode,
        phase: row.phase,
        plannedSeconds: row.plannedSeconds,
        actualSeconds: row.actualSeconds,
        completed: row.completed,
        taskId: row.taskId,
        taskTitle: row.taskTitle,
      ),
  ]);
}
