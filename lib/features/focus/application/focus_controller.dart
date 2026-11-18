import 'dart:async';

import 'package:flutter/services.dart' show MethodChannel;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../domain/plan/step_progress.dart';

enum FocusStatus { idle, running, paused, completed }

class FocusSessionState {
  const FocusSessionState({
    this.status = FocusStatus.idle,
    this.phase = 'focus',
    this.taskId,
    this.stepId,
    this.taskTitle,
    this.subjectName,
    this.plannedSeconds = 0,
    this.startedAt,
    this.targetEndAt,
    this.remainingSeconds = 0,
    this.awaitingCompletion = false,
  });

  final FocusStatus status;
  final String phase;
  final String? taskId;
  final String? stepId;
  final String? taskTitle;
  final String? subjectName;
  final int plannedSeconds;
  final DateTime? startedAt;
  final DateTime? targetEndAt;
  final int remainingSeconds;
  final bool awaitingCompletion;

  bool get isRunning => status == FocusStatus.running;
  bool get isPaused => status == FocusStatus.paused;

  FocusSessionState copyWith({
    FocusStatus? status,
    String? phase,
    String? taskId,
    String? stepId,
    String? taskTitle,
    String? subjectName,
    int? plannedSeconds,
    DateTime? startedAt,
    DateTime? targetEndAt,
    int? remainingSeconds,
    bool? awaitingCompletion,
  }) {
    return FocusSessionState(
      status: status ?? this.status,
      phase: phase ?? this.phase,
      taskId: taskId ?? this.taskId,
      stepId: stepId ?? this.stepId,
      taskTitle: taskTitle ?? this.taskTitle,
      subjectName: subjectName ?? this.subjectName,
      plannedSeconds: plannedSeconds ?? this.plannedSeconds,
      startedAt: startedAt ?? this.startedAt,
      targetEndAt: targetEndAt ?? this.targetEndAt,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      awaitingCompletion: awaitingCompletion ?? this.awaitingCompletion,
    );
  }
}

class FocusController extends Notifier<FocusSessionState> {
  static const _channel = MethodChannel('khutati/focus_timer');

  Timer? _ticker;
  int _pausedRemaining = 0;

  @override
  FocusSessionState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const FocusSessionState();
  }

  Future<void> start({
    required int plannedSeconds,
    String phase = 'focus',
    String? taskId,
    String? stepId,
    String? taskTitle,
    String? subjectName,
  }) async {
    _ticker?.cancel();
    final now = DateTime.now();
    final target = now.add(Duration(seconds: plannedSeconds));
    state = FocusSessionState(
      status: FocusStatus.running,
      phase: phase,
      taskId: taskId,
      stepId: stepId,
      taskTitle: taskTitle,
      subjectName: subjectName,
      plannedSeconds: plannedSeconds,
      startedAt: now,
      targetEndAt: target,
      remainingSeconds: plannedSeconds,
      awaitingCompletion: false,
    );
    _startTicker();
    await _nativeStart(plannedSeconds, taskId, stepId);
  }

  void pause() {
    if (state.status != FocusStatus.running) return;
    _ticker?.cancel();
    _pausedRemaining = state.remainingSeconds;
    state = state.copyWith(status: FocusStatus.paused);
    _nativeStop();
  }

  Future<void> resume() async {
    if (state.status != FocusStatus.paused) return;
    final now = DateTime.now();
    final target = now.add(Duration(seconds: _pausedRemaining));
    state = state.copyWith(
      status: FocusStatus.running,
      targetEndAt: target,
      remainingSeconds: _pausedRemaining,
    );
    _startTicker();
    await _nativeStart(_pausedRemaining, state.taskId, state.stepId);
  }

  Future<void> end() async {
    _ticker?.cancel();
    final actual = _elapsed();
    await _logSession(completed: false, actualSeconds: actual);
    await _nativeStop();
    state = const FocusSessionState();
  }

  Future<void> complete() async {
    _ticker?.cancel();
    final actual = state.plannedSeconds;
    await _logSession(completed: true, actualSeconds: actual);
    await _nativeStop();
    state = state.copyWith(
      status: FocusStatus.completed,
      remainingSeconds: 0,
      awaitingCompletion: state.taskId != null,
    );
  }

  Future<void> markTaskCompleted() async {
    final String? taskId = state.taskId;
    final String? stepId = state.stepId;
    if (taskId == null) return;
    final UserStateRepository repo = ref.read(userStateRepositoryProvider);
    if (stepId != null) {
      await repo.setStepCompleted(stepId, StepProgress.completed);
    }
    await repo.setTaskStatus(taskId, 'completed');
    state = state.copyWith(awaitingCompletion: false);
  }

  void dismissCompletion() {
    state = state.copyWith(awaitingCompletion: false);
  }

  void reset() {
    _ticker?.cancel();
    state = const FocusSessionState();
  }

  int _elapsed() {
    if (state.startedAt == null) return 0;
    final int planned = state.plannedSeconds;
    final int remaining = state.remainingSeconds;
    final int elapsed = planned - remaining;
    return elapsed.clamp(0, planned);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final DateTime? target = state.targetEndAt;
      if (target == null) return;
      final int remaining = target.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        state = state.copyWith(remainingSeconds: 0);
        complete();
      } else {
        state = state.copyWith(remainingSeconds: remaining);
      }
    });
  }

  Future<void> _nativeStart(int seconds, String? taskId, String? stepId) async {
    try {
      await _channel.invokeMethod<void>('start', <String, dynamic>{
        'durationMs': seconds * 1000,
        'taskId': taskId,
        'stepId': stepId,
      });
    } catch (_) {
      // Native service unavailable; in-app timer still runs.
    }
  }

  Future<void> _nativeStop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> _logSession({
    required bool completed,
    required int actualSeconds,
  }) async {
    final DateTime started = state.startedAt ?? DateTime.now();
    final AppDatabase db = ref.read(appDatabaseProvider);
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            taskId: Value<String?>(state.taskId),
            stepId: Value<String?>(state.stepId),
            phase: state.phase,
            plannedSeconds: state.plannedSeconds,
            actualSeconds: actualSeconds,
            startedAt: started,
            endedAt: Value<DateTime>(DateTime.now()),
            completed: Value<bool>(completed),
          ),
        );
  }
}

final focusControllerProvider =
    NotifierProvider<FocusController, FocusSessionState>(FocusController.new);
