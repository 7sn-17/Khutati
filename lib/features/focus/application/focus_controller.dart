import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drift/drift.dart';

import '../../../core/settings/theme_mode_controller.dart'
    show sharedPreferencesProvider;
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
    this.phase = FocusPhases.focus,
    this.taskId,
    this.stepId,
    this.taskTitle,
    this.subjectName,
    this.plannedSeconds = 0,
    this.startedAt,
    this.targetEndAt,
    this.remainingSeconds = 0,
    this.awaitingCompletion = false,
    this.awaitingResume = false,
    this.nextStepId,
    this.nextStepTitle,
    this.nextStepPlannedSeconds,
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
  final bool awaitingResume;
  final String? nextStepId;
  final String? nextStepTitle;
  final int? nextStepPlannedSeconds;

  bool get isRunning => status == FocusStatus.running;
  bool get isPaused => status == FocusStatus.paused;
  bool get isBreak => phase == FocusPhases.breakTime;

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
    bool? awaitingResume,
    String? nextStepId,
    String? nextStepTitle,
    int? nextStepPlannedSeconds,
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
      awaitingResume: awaitingResume ?? this.awaitingResume,
      nextStepId: nextStepId ?? this.nextStepId,
      nextStepTitle: nextStepTitle ?? this.nextStepTitle,
      nextStepPlannedSeconds:
          nextStepPlannedSeconds ?? this.nextStepPlannedSeconds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status.name,
    'phase': phase,
    'taskId': taskId,
    'stepId': stepId,
    'taskTitle': taskTitle,
    'subjectName': subjectName,
    'plannedSeconds': plannedSeconds,
    'startedAt': startedAt?.toIso8601String(),
    'targetEndAt': targetEndAt?.toIso8601String(),
    'remainingSeconds': remainingSeconds,
    'awaitingCompletion': awaitingCompletion,
    'awaitingResume': awaitingResume,
    'nextStepId': nextStepId,
    'nextStepTitle': nextStepTitle,
    'nextStepPlannedSeconds': nextStepPlannedSeconds,
  };

  static FocusSessionState? fromJson(Map<String, dynamic> json) {
    final String? statusName = json['status'] as String?;
    final FocusStatus status = FocusStatus.values.firstWhere(
      (FocusStatus value) => value.name == statusName,
      orElse: () => FocusStatus.idle,
    );
    if (status == FocusStatus.idle) return null;
    return FocusSessionState(
      status: status,
      phase: (json['phase'] as String?) ?? FocusPhases.focus,
      taskId: json['taskId'] as String?,
      stepId: json['stepId'] as String?,
      taskTitle: json['taskTitle'] as String?,
      subjectName: json['subjectName'] as String?,
      plannedSeconds: (json['plannedSeconds'] as num?)?.toInt() ?? 0,
      startedAt: _parseDate(json['startedAt']),
      targetEndAt: _parseDate(json['targetEndAt']),
      remainingSeconds: (json['remainingSeconds'] as num?)?.toInt() ?? 0,
      awaitingCompletion: json['awaitingCompletion'] == true,
      awaitingResume: json['awaitingResume'] == true,
      nextStepId: json['nextStepId'] as String?,
      nextStepTitle: json['nextStepTitle'] as String?,
      nextStepPlannedSeconds: (json['nextStepPlannedSeconds'] as num?)?.toInt(),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

// Back-compat alias for the pure domain phase constants.
abstract final class FocusPhases {
  static const String focus = 'focus';
  static const String breakTime = 'break';
}

class FocusController extends Notifier<FocusSessionState> {
  static const _channel = MethodChannel('khutati/focus_timer');
  static const _sessionKey = 'focus_session_v1';

  Timer? _ticker;
  int _pausedRemaining = 0;
  bool _restored = false;

  @override
  FocusSessionState build() {
    ref.onDispose(() => _ticker?.cancel());
    Future<void>.microtask(_restore);
    return const FocusSessionState();
  }

  Future<void> start({
    required int plannedSeconds,
    String phase = FocusPhases.focus,
    String? taskId,
    String? stepId,
    String? taskTitle,
    String? subjectName,
    String? nextStepId,
    String? nextStepTitle,
    int? nextStepPlannedSeconds,
  }) async {
    _ticker?.cancel();
    final now = DateTime.now();
    final target = now.add(Duration(seconds: plannedSeconds));
    _pausedRemaining = 0;
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
      awaitingResume: false,
      nextStepId: nextStepId,
      nextStepTitle: nextStepTitle,
      nextStepPlannedSeconds: nextStepPlannedSeconds,
    );
    _startTicker();
    await _nativeStart(
      plannedSeconds,
      taskId,
      stepId,
      phase,
      taskTitle,
      nextStepId != null || (nextStepPlannedSeconds ?? 0) > 0,
    );
    if (taskId != null) {
      try {
        await ref
            .read(userStateRepositoryProvider)
            .setTaskStatus(taskId, 'in_progress');
      } catch (_) {}
    }
    _persist();
  }

  void pause() {
    if (state.status != FocusStatus.running) return;
    _ticker?.cancel();
    _pausedRemaining = state.remainingSeconds;
    state = state.copyWith(status: FocusStatus.paused);
    _nativePause();
    _persist();
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
    await _nativeResume(_pausedRemaining);
    _persist();
  }

  /// Ends the current step early: marks it completed when the timer finished,
  /// otherwise partial, logs the real elapsed time, then moves immediately to
  /// the next step when one exists.
  Future<void> end() => endSession();

  Future<void> endSession() async {
    _ticker?.cancel();
    final bool finished = state.remainingSeconds <= 0;
    final int actual = _elapsed();
    await _logSession(completed: finished, actualSeconds: actual);

    final String? stepId = state.stepId;
    final String? taskId = state.taskId;
    if (stepId != null) {
      try {
        await ref.read(userStateRepositoryProvider).setStepCompleted(
          stepId,
          finished ? StepProgress.completed : StepProgress.partial,
        );
      } catch (_) {}
    }
    if (taskId != null && state.nextStepPlannedSeconds == null) {
      try {
        await ref.read(userStateRepositoryProvider).setTaskStatus(taskId, 'completed');
      } catch (_) {}
    } else if (taskId != null) {
      try {
        await ref.read(userStateRepositoryProvider).setTaskStatus(taskId, 'in_progress');
      } catch (_) {}
    }

    await _nativeStop();
    final int? nextSeconds = state.nextStepPlannedSeconds;
    if (nextSeconds != null && nextSeconds > 0) {
      await start(
        plannedSeconds: nextSeconds,
        phase: FocusPhases.focus,
        taskId: taskId,
        stepId: state.nextStepId,
        taskTitle: state.taskTitle,
        subjectName: state.subjectName,
      );
      return;
    }
    state = state.copyWith(
      status: FocusStatus.completed,
      remainingSeconds: 0,
      awaitingCompletion: taskId != null,
      awaitingResume: false,
    );
    _persist();
  }

  /// Skips the current step without marking it complete, logs the elapsed time,
  /// then moves immediately to the next step when one exists.
  Future<void> skipStep() async {
    _ticker?.cancel();
    final int actual = _elapsed();
    await _logSession(completed: false, actualSeconds: actual);
    await _nativeStop();
    final int? nextSeconds = state.nextStepPlannedSeconds;
    final String? taskId = state.taskId;
    if (nextSeconds != null && nextSeconds > 0) {
      await start(
        plannedSeconds: nextSeconds,
        phase: FocusPhases.focus,
        taskId: taskId,
        stepId: state.nextStepId,
        taskTitle: state.taskTitle,
        subjectName: state.subjectName,
      );
      return;
    }
    state = const FocusSessionState();
    _persist();
  }

  Future<void> complete() async {
    _ticker?.cancel();
    final int actual =
        state.plannedSeconds > 0 ? state.plannedSeconds : _elapsed();
    await _logSession(completed: true, actualSeconds: actual);
    if (state.phase == FocusPhases.focus) {
      state = state.copyWith(
        status: FocusStatus.completed,
        remainingSeconds: 0,
        awaitingCompletion: state.taskId != null,
        awaitingResume: false,
      );
    } else {
      state = state.copyWith(
        status: FocusStatus.completed,
        remainingSeconds: 0,
        awaitingCompletion: false,
        awaitingResume: true,
      );
    }
    _persist();
    await _syncNativeRemaining();
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
    _persist();
  }

  Future<void> startNextStep() async {
    final int? seconds = state.nextStepPlannedSeconds;
    if (seconds == null || seconds <= 0) return;
    final String? taskId = state.taskId;
    final String? currentStepId = state.stepId;
    if (taskId != null && currentStepId != null) {
      try {
        await ref
            .read(userStateRepositoryProvider)
            .setStepCompleted(currentStepId, StepProgress.completed);
      } catch (_) {}
    }
    await start(
      plannedSeconds: seconds,
      phase: FocusPhases.focus,
      taskId: taskId,
      stepId: state.nextStepId,
      taskTitle: state.taskTitle,
      subjectName: state.subjectName,
    );
  }

  Future<void> resumeFromBreak() async {
    state = state.copyWith(awaitingResume: false);
    final int? seconds = state.nextStepPlannedSeconds;
    if (seconds != null && seconds > 0) {
      await start(
        plannedSeconds: seconds,
        phase: FocusPhases.focus,
        taskId: state.taskId,
        stepId: state.nextStepId,
        taskTitle: state.taskTitle,
        subjectName: state.subjectName,
      );
      return;
    }
    await start(
      plannedSeconds: 25 * 60,
      phase: FocusPhases.focus,
      taskId: state.taskId,
      taskTitle: state.taskTitle ?? 'تركيز',
      subjectName: state.subjectName,
    );
  }

  Future<void> consumePendingAction() async {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final String? action = prefs.getString('pending_focus_action');
      if (action == null || action.isEmpty) return;
      await prefs.remove('pending_focus_action');
      if (action == 'skip_step') {
        await skipStep();
      } else if (action == 'start_break') {
        // Native already handles the transition; refresh state.
        await _syncNativeRemaining();
      }
    } catch (_) {}
  }

  bool get hasNextStep =>
      state.nextStepId != null || (state.nextStepPlannedSeconds ?? 0) > 0;

  void dismissCompletion() {
    state = state.copyWith(awaitingCompletion: false);
    _persist();
  }

  void dismissResume() {
    state = state.copyWith(awaitingResume: false);
    _persist();
  }

  void reset() {
    _ticker?.cancel();
    state = const FocusSessionState();
    _persist();
  }

  void skipBreak() {
    _ticker?.cancel();
    _nativeStop();
    state = state.copyWith(
      status: FocusStatus.completed,
      phase: FocusPhases.focus,
      remainingSeconds: 0,
      awaitingResume: true,
    );
    _persist();
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
      if (target == null || state.status != FocusStatus.running) return;
      final int remaining = target.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        state = state.copyWith(remainingSeconds: 0);
        complete();
      } else {
        state = state.copyWith(remainingSeconds: remaining);
      }
      _syncNativeRemaining();
    });
  }

  Future<void> _syncNativeRemaining() async {
    try {
      final Map<dynamic, dynamic>? native = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getState');
      if (native == null) return;
      final bool paused = native['paused'] == true;
      final int remainingMs = (native['remainingMs'] as num?)?.toInt() ?? 0;
      final String nativePhase =
          (native['phase'] as String?) ?? state.phase;

      if (paused && state.status == FocusStatus.running) {
        pause();
      }

      if (remainingMs > 0) {
        if (nativePhase != state.phase &&
            state.status != FocusStatus.idle) {
          if (nativePhase == FocusPhases.breakTime &&
              state.phase == FocusPhases.focus) {
            if (state.status == FocusStatus.running) {
              await _logSession(
                completed: true,
                actualSeconds: state.plannedSeconds,
              );
            }
            state = state.copyWith(
              status: FocusStatus.running,
              phase: FocusPhases.breakTime,
              remainingSeconds: (remainingMs / 1000).ceil(),
              targetEndAt: DateTime.now().add(
                Duration(milliseconds: remainingMs),
              ),
              awaitingCompletion: state.taskId != null,
              awaitingResume: false,
            );
            _persist();
            return;
          }
          if (nativePhase == FocusPhases.focus &&
              state.phase == FocusPhases.breakTime) {
            state = state.copyWith(
              status: FocusStatus.running,
              phase: FocusPhases.focus,
              remainingSeconds: (remainingMs / 1000).ceil(),
              targetEndAt: DateTime.now().add(
                Duration(milliseconds: remainingMs),
              ),
            );
            _persist();
            return;
          }
        }
        state = state.copyWith(
          remainingSeconds: (remainingMs / 1000).ceil(),
          phase: nativePhase,
          targetEndAt: state.status == FocusStatus.running
              ? DateTime.now().add(Duration(milliseconds: remainingMs))
              : state.targetEndAt,
        );
        _persist();
      } else if (state.status == FocusStatus.running) {
        if (state.phase == FocusPhases.focus) {
          await _logSession(
            completed: true,
            actualSeconds: state.plannedSeconds,
          );
          state = state.copyWith(
            status: FocusStatus.completed,
            remainingSeconds: 0,
            awaitingCompletion: state.taskId != null,
          );
        } else {
          await _logSession(
            completed: true,
            actualSeconds: state.plannedSeconds,
          );
          state = state.copyWith(
            status: FocusStatus.completed,
            remainingSeconds: 0,
            awaitingResume: true,
          );
        }
        _persist();
      }
      if (state.status == FocusStatus.paused) {
        _pausedRemaining = state.remainingSeconds;
      }
    } catch (_) {}
  }

  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final String? raw = prefs.getString(_sessionKey);
      if (raw == null || raw.isEmpty) return;
      final Map<String, dynamic> json = (jsonDecode(raw) as Map)
          .cast<String, dynamic>();
      final FocusSessionState? saved = FocusSessionState.fromJson(json);
      if (saved == null) return;

      final Map<dynamic, dynamic> native = await _nativeGetState();
      final bool nativePaused = native['paused'] == true;
      final int nativeRemainingMs =
          (native['remainingMs'] as num?)?.toInt() ?? 0;
      final String nativePhase = (native['phase'] as String?) ?? saved.phase;

      // If the native timer expired and advanced the phase (for example focus ->
      // break while the app was killed), log the completed phase first.
      if (saved.status == FocusStatus.running &&
          saved.phase == FocusPhases.focus &&
          nativePhase == FocusPhases.breakTime &&
          nativeRemainingMs > 0) {
        await _logState(saved, completed: true);
      }

      int remaining = saved.remainingSeconds;
      if (nativeRemainingMs > 0) {
        remaining = (nativeRemainingMs / 1000).ceil();
      }

      if (saved.status == FocusStatus.running && nativeRemainingMs <= 0) {
        // The phase finished while we were away.
        if (saved.phase == FocusPhases.focus) {
          await _logState(saved, completed: true);
          state = FocusSessionState(
            status: FocusStatus.completed,
            phase: FocusPhases.focus,
            taskId: saved.taskId,
            stepId: saved.stepId,
            taskTitle: saved.taskTitle,
            subjectName: saved.subjectName,
            plannedSeconds: saved.plannedSeconds,
            startedAt: saved.startedAt,
            remainingSeconds: 0,
            awaitingCompletion: saved.taskId != null,
            awaitingResume: false,
            nextStepId: saved.nextStepId,
            nextStepTitle: saved.nextStepTitle,
            nextStepPlannedSeconds: saved.nextStepPlannedSeconds,
          );
          _persist();
          return;
        }
        await _logState(saved, completed: true);
        state = const FocusSessionState(
          status: FocusStatus.completed,
          phase: FocusPhases.focus,
          awaitingResume: true,
        );
        _persist();
        return;
      }

      final FocusStatus status = nativePaused
          ? FocusStatus.paused
          : (remaining > 0 ? FocusStatus.running : saved.status);
      if (status == FocusStatus.paused) {
        _pausedRemaining = remaining > 0 ? remaining : saved.remainingSeconds;
      }

      state = saved.copyWith(
        status: status,
        phase: nativeRemainingMs > 0 ? nativePhase : saved.phase,
        remainingSeconds: remaining > 0 ? remaining : saved.remainingSeconds,
        targetEndAt: status == FocusStatus.running
            ? DateTime.now().add(
                Duration(
                  seconds: remaining > 0 ? remaining : saved.remainingSeconds,
                ),
              )
            : saved.targetEndAt,
      );

      if (status == FocusStatus.running) {
        _startTicker();
      }
      _persist();
    } catch (_) {
      // Leave the app in a safe idle state if restoration fails.
    }
  }

  Future<void> _nativeStart(
    int seconds,
    String? taskId,
    String? stepId,
    String phase,
    String? taskTitle,
    bool hasNextStep,
  ) async {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      await _channel.invokeMethod<void>('start', <String, dynamic>{
        'durationMs': seconds * 1000,
        'taskId': taskId,
        'stepId': stepId,
        'phase': phase,
        'taskTitle': taskTitle,
        'hasNextStep': hasNextStep,
        'breakEnabled': prefs.getBool('focus_break_enabled') ?? true,
        'breakMinutes': prefs.getInt('focus_break_minutes') ?? 5,
      });
    } catch (_) {
      // Native service unavailable; in-app timer still runs.
    }
  }

  Future<void> _nativePause() async {
    try {
      await _channel.invokeMethod<void>('pause');
    } catch (_) {}
  }

  Future<void> _nativeResume(int seconds) async {
    try {
      await _channel.invokeMethod<void>('resume', <String, dynamic>{
        'durationMs': seconds * 1000,
      });
    } catch (_) {}
  }

  Future<void> _nativeStop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<Map<dynamic, dynamic>> _nativeGetState() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getState');
      return result ?? <dynamic, dynamic>{};
    } catch (_) {
      return <dynamic, dynamic>{};
    }
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

  Future<void> _logState(
    FocusSessionState saved, {
    required bool completed,
  }) async {
    final DateTime started = saved.startedAt ?? DateTime.now();
    final AppDatabase db = ref.read(appDatabaseProvider);
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            taskId: Value<String?>(saved.taskId),
            stepId: Value<String?>(saved.stepId),
            phase: saved.phase,
            plannedSeconds: saved.plannedSeconds,
            actualSeconds: saved.plannedSeconds,
            startedAt: started,
            endedAt: Value<DateTime>(DateTime.now()),
            completed: Value<bool>(completed),
          ),
        );
  }

  bool get _breakEnabled {
    try {
      return ref
              .read(sharedPreferencesProvider)
              .getBool('focus_break_enabled') ??
          true;
    } catch (_) {
      return true;
    }
  }

  int get _breakSeconds {
    try {
      final int minutes =
          ref.read(sharedPreferencesProvider).getInt('focus_break_minutes') ??
          5;
      return minutes * 60;
    } catch (_) {
      return 5 * 60;
    }
  }

  void _persist() {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      if (state.status == FocusStatus.idle) {
        prefs.remove(_sessionKey);
        return;
      }
      prefs.setString(_sessionKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }
}

final focusControllerProvider =
    NotifierProvider<FocusController, FocusSessionState>(FocusController.new);

/// Whether the Focus screen is currently in user-controlled immersive mode.
/// Watched by [AppShell] so the bottom navigation bar disappears only when the
/// user opts in, never automatically when a session starts.
final StateProvider<bool> focusImmersiveProvider =
    StateProvider<bool>((Ref ref) => false);
