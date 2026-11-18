import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Durable, deduplicated outbox between SQLite and Supabase.
///
/// Writes are cheap and local; the uploader drains this table in batches. A
/// repeated edit of the same entity replaces the queued snapshot, so tapping a
/// step four times produces one upload with the final state.
class SyncQueueRepository {
  SyncQueueRepository(this._db);

  final AppDatabase _db;

  Future<void> enqueue(
    String entity,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    final DateTime now = DateTime.now();
    await _db
        .into(_db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            entity: entity,
            entityId: entityId,
            payload: jsonEncode(payload),
            enqueuedAt: now,
          ),
          // The auto-increment id is not the identity that deduplicates the
          // outbox: (entity, entityId) is. Without an explicit conflict target
          // Drift would only handle a primary-key clash and a repeated edit
          // would throw on the unique index instead of replacing the snapshot.
          onConflict: DoUpdate(
            ($SyncQueueTable old) => SyncQueueCompanion(
              payload: Value<String>(jsonEncode(payload)),
              enqueuedAt: Value<DateTime>(now),
              attempts: const Value<int>(0),
            ),
            target: <Column>[
              _db.syncQueue.entity,
              _db.syncQueue.entityId,
            ],
          ),
        );
  }

  Future<List<SyncQueueRow>> pending({int limit = 400}) {
    return (_db.select(_db.syncQueue)
          ..orderBy(<OrderingTerm Function($SyncQueueTable)>[
            ($SyncQueueTable t) => OrderingTerm.asc(t.enqueuedAt),
            // Taps inside the same millisecond must still drain in the order
            // they happened; the auto-increment id is the stable tiebreaker.
            ($SyncQueueTable t) => OrderingTerm.asc(t.id),
          ])
          ..limit(limit))
        .get();
  }

  Future<int> count() async {
    final Expression<int> countExp = _db.syncQueue.id.count();
    final TypedResult row = await (_db.selectOnly(_db.syncQueue)
          ..addColumns(<Expression<Object>>[countExp]))
        .getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<void> removeIds(Iterable<int> ids) async {
    final List<int> values = ids.toList(growable: false);
    if (values.isEmpty) return;
    await (_db.delete(_db.syncQueue)
          ..where(($SyncQueueTable t) => t.id.isIn(values)))
        .go();
  }

  Future<void> recordFailure(Iterable<int> ids) async {
    final List<int> values = ids.toList(growable: false);
    if (values.isEmpty) return;
    await _db.customUpdate(
      'UPDATE sync_queue SET attempts = attempts + 1 WHERE id IN (${values.map((_) => '?').join(',')})',
      variables: <Variable>[
        for (final int id in values) Variable<int>(id),
      ],
      // A raw UPDATE still has to name the table it touches, or Drift cannot
      // invalidate the `pending()` query streams that depend on it.
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.syncQueue},
    );
  }
}
