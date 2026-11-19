import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/data/sync/task_state_merge.dart';

void main() {
  final DateTime completedAt = DateTime.utc(2026, 11, 19, 12, 2);
  final DateTime reopenedAt = DateTime.utc(2026, 11, 19, 12, 3);

  test('a later uncompleted step makes a remote completion stale', () {
    expect(
      remoteTaskStateIsStale(
        remoteStatus: 'completed',
        remoteUpdatedAt: completedAt,
        localSteps: <LocalStepStamp>[(updatedAt: reopenedAt, completed: false)],
      ),
      isTrue,
    );
  });

  test('a remote completion newer than the step edit still wins', () {
    expect(
      remoteTaskStateIsStale(
        remoteStatus: 'completed',
        remoteUpdatedAt: reopenedAt,
        localSteps: <LocalStepStamp>[
          (updatedAt: completedAt, completed: false),
        ],
      ),
      isFalse,
    );
  });

  test('a later completed step does not stale the task completion', () {
    expect(
      remoteTaskStateIsStale(
        remoteStatus: 'completed',
        remoteUpdatedAt: completedAt,
        localSteps: <LocalStepStamp>[(updatedAt: reopenedAt, completed: true)],
      ),
      isFalse,
    );
  });

  test('a step edit before the completion is not newer intent', () {
    expect(
      remoteTaskStateIsStale(
        remoteStatus: 'completed',
        remoteUpdatedAt: reopenedAt,
        localSteps: <LocalStepStamp>[
          (updatedAt: completedAt, completed: false),
        ],
      ),
      isFalse,
    );
  });

  test('non-completed remote statuses are never stale', () {
    expect(
      remoteTaskStateIsStale(
        remoteStatus: 'in_progress',
        remoteUpdatedAt: completedAt,
        localSteps: <LocalStepStamp>[(updatedAt: reopenedAt, completed: false)],
      ),
      isFalse,
    );
  });
}
