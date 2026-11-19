/// A local step edit with the timestamp that decides whether a remote task
/// completion is still current.
typedef LocalStepStamp = ({DateTime updatedAt, bool completed});

/// Whether a remote task state is older than a local step edit that reopened
/// the task.
///
/// A completed task is an explicit "every step is done" statement, and the app
/// deliberately does not rewrite the user's step rows when a task is closed.
/// That means a remote `completed` row can outlive a later step edit. If any
/// local step was changed after the remote task row and is no longer complete,
/// the step edit is the newer intent: keep the local state and let the outbox
/// push the reopened task instead of painting the step back to complete.
bool remoteTaskStateIsStale({
  required String remoteStatus,
  required DateTime remoteUpdatedAt,
  required Iterable<LocalStepStamp> localSteps,
}) {
  if (remoteStatus != 'completed') return false;
  for (final LocalStepStamp step in localSteps) {
    if (!step.completed &&
        step.updatedAt.toUtc().isAfter(remoteUpdatedAt.toUtc())) {
      return true;
    }
  }
  return false;
}
