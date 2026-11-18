import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/repositories/sync_queue_repository.dart';

/// The outbox is the contract between "save instantly" and "upload in
/// batches". These tests pin the two properties the sync service relies on:
///
/// * repeated writes of one entity collapse into one row (one network write
///   per entity, not one per tap);
/// * a drain only removes rows the server acknowledged, so a partial outage
///   never loses progress.
void main() {
  late AppDatabase db;
  late SyncQueueRepository queue;

  setUp(() {
    db = AppDatabase.memory();
    queue = SyncQueueRepository(db);
  });

  tearDown(() => db.close());

  test('repeated writes for one entity coalesce into one snapshot', () async {
    await queue.enqueue('step_state', 'step-1', <String, Object?>{
      'progress': 1,
    });
    await queue.enqueue('step_state', 'step-1', <String, Object?>{
      'progress': 2,
    });
    await queue.enqueue('step_state', 'step-1', <String, Object?>{
      'progress': 3,
    });

    final List<SyncQueueRow> rows = await queue.pending();

    expect(rows, hasLength(1));
    expect(rows.single.entity, 'step_state');
    expect(rows.single.entityId, 'step-1');
    expect(rows.single.payload, contains('"progress":3'));
    expect(await queue.count(), 1);
  });

  test('different entities are kept separately in enqueue order', () async {
    await queue.enqueue('step_state', 'step-1', <String, Object?>{
      'progress': 1,
    });
    await queue.enqueue('task_state', 'task-1', <String, Object?>{
      'status': 'completed',
    });
    await queue.enqueue('focus_session', 'session-1', <String, Object?>{
      'completed': true,
    });

    final List<SyncQueueRow> rows = await queue.pending();

    expect(rows.map((SyncQueueRow row) => row.entity), <String>[
      'step_state',
      'task_state',
      'focus_session',
    ]);
    expect(rows.map((SyncQueueRow row) => row.entityId), <String>[
      'step-1',
      'task-1',
      'session-1',
    ]);
  });

  test('a batch is capped without dropping the rest of the outbox', () async {
    for (int i = 0; i < 7; i++) {
      await queue.enqueue('step_state', 'step-$i', <String, Object?>{
        'progress': i,
      });
    }

    final List<SyncQueueRow> batch = await queue.pending(limit: 3);

    expect(batch, hasLength(3));
    expect(await queue.count(), 7);
    // The cap takes the oldest rows, so a backlog drains oldest-first.
    expect(
      batch.map((SyncQueueRow row) => row.entityId),
      <String>['step-0', 'step-1', 'step-2'],
    );
  });

  test('only acknowledged rows are removed and failures are counted', () async {
    await queue.enqueue('step_state', 'ok', <String, Object?>{'progress': 2});
    await queue.enqueue('step_state', 'retry', <String, Object?>{'progress': 1});

    final List<SyncQueueRow> rows = await queue.pending();
    await queue.removeIds(<int>[rows.first.id]);
    await queue.recordFailure(<int>[rows.last.id]);

    final List<SyncQueueRow> left = await queue.pending();

    expect(left, hasLength(1));
    expect(left.single.entityId, 'retry');
    expect(left.single.attempts, 1);
  });

  test('re-enqueueing resets attempts and keeps one stable row', () async {
    await queue.enqueue('step_state', 'step-1', <String, Object?>{
      'progress': 1,
    });
    final SyncQueueRow first = (await queue.pending()).single;
    await queue.recordFailure(<int>[first.id]);

    await queue.enqueue('step_state', 'step-1', <String, Object?>{
      'progress': 3,
    });
    final SyncQueueRow again = (await queue.pending()).single;

    expect(again.id, first.id);
    expect(again.attempts, 0);
    expect(again.payload, contains('"progress":3'));
  });

  test('empty id sets are a no-op', () async {
    await queue.enqueue('step_state', 'step-1', <String, Object?>{
      'progress': 1,
    });

    await queue.removeIds(const <int>[]);
    await queue.recordFailure(const <int>[]);

    final SyncQueueRow row = (await queue.pending()).single;
    expect(row.attempts, 0);
    expect(await queue.count(), 1);
  });
}
