import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/settings/theme_mode_controller.dart'
    show sharedPreferencesProvider;
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../domain/plan/step_progress.dart';
import '../domain/focus_setup.dart';

/// Immutable snapshot of the focus state machine.
///
/// The machine has exactly four stages ([FocusStage]); the UI renders one
/// screen per stage and never has to infer anything from a set of booleans.
class FocusSessionState {
  const FocusSessionState({
    this.stage = FocusStage.idle,
    this.phase = FocusPhase.focus,
    this.mode = FocusMode.pomodoro,
    this.taskId,
    this.taskTitle,
    this.subjectName,
    this.steps = const <FocusStepRef>[],
    this.stepIndex = 0,
    this.plannedSeconds = 0,
    this.remainingSeconds = 0,
    this.startedAt,
    this.endsAt,
    this.breakMinutes = 0,
    this.autoBreak = false,
    this.recordedSeconds = 0,
    this.reason,
    this.rounds = 0,
  });

  final FocusStage stage;
  final FocusPhase phase;
  final FocusMode mode;

  final String? taskId;
  final String? taskTitle;
  final String? subjectName;

  /// The remaining step chain of a linked task, so "next step" stays correct
  /// for two- and three-step tasks without another database read.
  final List<FocusStepRef> steps;
  final int stepIndex;

  final int plannedSeconds;
  final int remainingSeconds;
  final DateTime? startedAt;
  final DateTime? endsAt;

  final int breakMinutes;
  final bool autoBreak;

  /// Seconds actually spent, captured when the session reaches `finished`.
  final int recordedSeconds;

  /// Why the session finished; `null` while it is still running.
  final FocusEndReason? reason;

  /// Completed focus rounds since the machine last left idle.
  final int rounds;

  bool get isIdle => stage == FocusStage.idle;
  bool get isRunning => stage == FocusStage.running;
  bool get isPaused => stage == FocusStage.paused;
  bool get isFinished => stage == FocusStage.finished;
  bool get isBreak => phase.isBreak;

  FocusStepRef? get currentStep =>
      steps.isEmpty ? null : steps[stepIndex.clamp(0, steps.length - 1)];

  FocusStepRef? get nextStep =>
      steps.isEmpty || stepIndex + 1 >= steps.length
      ? null
      : steps[stepIndex + 1];

  bool get hasNextStep => nextStep != null;

  /// 1 → full arc (just started), 0 → empty arc.
  double get progress =>
      plannedSeconds <= 0 ? 0 : remainingSeconds / plannedSeconds;

  bool get recordedStepAsDone =>
      mode == FocusMode.linked &&
      currentStep != null &&
      reason != FocusEndReason.skipped;

  FocusSessionState copyWith({
    FocusStage? stage,
    FocusPhase? phase,
    FocusMode? mode,
    String? taskId,
    String? taskTitle,
    String? subjectName,
    List<FocusStepRef>? steps,
    int? stepIndex,
    int? plannedSeconds,
    int? remainingSeconds,
    DateTime? startedAt,
    DateTime? endsAt,
    int? breakMinutes,
    bool? autoBreak,
    int? recordedSeconds,
    FocusEndReason? reason,
    int? rounds,
  }) {
    return FocusSessionState(
      stage: stage ?? this.stage,
      phase: phase ?? this.phase,
      mode: mode ?? this.mode,
      taskId: taskId ?? this.taskId,
      taskTitle: taskTitle ?? this.taskTitle,
      subjectName: subjectName ?? this.subjectName,
      steps: steps ?? this.steps,
      stepIndex: stepIndex ?? this.stepIndex,
      plannedSeconds: plannedSeconds ?? this.plannedSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      startedAt: startedAt ?? this.startedAt,
      endsAt: endsAt ?? this.endsAt,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      autoBreak: autoBreak ?? this.autoBreak,
      recordedSeconds: recordedSeconds ?? this.recordedSeconds,
      reason: reason ?? this.reason,
      rounds: rounds ?? this.rounds,
    );
  }

  /// Rebuilds the full snapshot for a terminal state, dropping timing fields
  /// that no longer apply. Keeping this explicit is what guarantees the UI can
  /// never render a half-finished session.
  FocusSessionState finish({
    required FocusEndReason reason,
    required int recordedSeconds,
  }) {
    return FocusSessionState(
      stage: FocusStage.finished,
      phase: phase,
      mode: mode,
      taskId: taskId,
      taskTitle: taskTitle,
      subjectName: subjectName,
      steps: steps,
      stepIndex: stepIndex,
      plannedSeconds: plannedSeconds,
      remainingSeconds: 0,
      breakMinutes: breakMinutes,
      autoBreak: autoBreak,
      recordedSeconds: recordedSeconds,
      reason: reason,
      rounds: rounds + (phase == FocusPhase.focus ? 1 : 0),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'stage': stage.name,
    'phase': phase.wire,
    'mode': mode.name,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'subjectName': subjectName,
    'steps': <Map<String, dynamic>>[
      for (final FocusStepRef step in steps) step.toJson(),
    ],
    'stepIndex': stepIndex,
    'plannedSeconds': plannedSeconds,
    'remainingSeconds': remainingSeconds,
    'startedAt': startedAt?.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'breakMinutes': breakMinutes,
    'autoBreak': autoBreak,
    'rounds': rounds,
  };

  /// Returns `null` for anything that must not survive a restart (idle or a
  /// completion screen), so reopening the app can never land on a dead session.
  static FocusSessionState? fromJson(Map<String, dynamic> json) {
    FocusStage stage = FocusStage.idle;
    for (final FocusStage value in FocusStage.values) {
      if (value.name == json['stage']) stage = value;
    }
    if (stage != FocusStage.running && stage != FocusStage.paused) return null;

    FocusMode mode = FocusMode.pomodoro;
    for (final FocusMode value in FocusMode.values) {
      if (value.name == json['mode']) mode = value;
    }

    int intOf(Object? raw, [int fallback = 0]) =>
        (raw as num?)?.toInt() ?? fallback;

    return FocusSessionState(
      stage: stage,
      phase: FocusPhase.parse(json['phase'] as String?),
      mode: mode,
      taskId: json['taskId'] as String?,
      taskTitle: json['taskTitle'] as String?,
      subjectName: json['subjectName'] as String?,
      steps: FocusStepRef.listFromJson(json['steps']),
      stepIndex: intOf(json['stepIndex']),
      plannedSeconds: intOf(json['plannedSeconds']),
      remainingSeconds: intOf(json['remainingSeconds']),
      startedAt: _parseDate(json['startedAt']),
      endsAt: _parseDate(json['endsAt']),
      breakMinutes: intOf(json['breakMinutes']),
      autoBreak: json['autoBreak'] == true,
      rounds: intOf(json['rounds']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

/// The focus state machine.
///
/// Rules the implementation guarantees:
/// * `idle` is the only entry point; every terminal path ends in `finished`,
///   and `finished` can only be dismissed back to `idle`.
/// * Ending a step (button or timer) always records the step as 100% complete;
///   skipping never touches progress.
/// * The in-app ticker is the single source of truth while the app is alive;
///   the Kotlin service is a mirror plus the source of truth after process
///   death.
class FocusController extends Notifier<FocusSessionState> {
  static const MethodChannel _channel = MethodChannel('khutati/focus_timer');
  static const String sessionKey = 'focus_session_v2';
  static const String pendingActionKey = 'pending_focus_action';

  Timer? _ticker;
  bool _restored = false;
  bool _busy = false;
  int _pausedRemaining = 0;

  @override
  FocusSessionState build() {
    ref.onDispose(() => _ticker?.cancel());
    Future<void>.microtask(_restore);
    return const FocusSessionState();
  }

  // ---------------------------------------------------------------- lifecycle

  /// Starts an idle-state session. [draft] is only meaningful for
  /// [FocusMode.linked]; the other modes run a bare countdown.
  Future<void> start({
    required FocusMode mode,
    required int minutes,
    int breakMinutes = 0,
    bool autoBreak = false,
    FocusTaskDraft? draft,
  }) async {
    if (minutes <= 0) return;
    _ticker?.cancel();
    _busy = false;
    _pausedRemaining = 0;

    final DateTime now = DateTime.now();
    final int seconds = minutes * 60;
    state = FocusSessionState(
      stage: FocusStage.running,
      phase: FocusPhase.focus,
      mode: mode,
      taskId: draft?.taskId,
      taskTitle: draft?.taskTitle,
      subjectName: draft?.subjectName,
      steps: draft?.steps ?? const <FocusStepRef>[],
      stepIndex: draft?.startIndex ?? 0,
      plannedSeconds: seconds,
      remainingSeconds: seconds,
      startedAt: now,
      endsAt: now.add(Duration(seconds: seconds)),
      breakMinutes: breakMinutes,
      autoBreak: autoBreak,
    );
    _startTicker();
    await _nativeStart(phase: FocusPhase.focus, seconds: seconds);
    await _markTaskInProgress();
    _persist();
  }

  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    _pausedRemaining = state.remainingSeconds;
    state = state.copyWith(stage: FocusStage.paused);
    unawaited(_nativePause());
    _persist();
  }

  Future<void> resume() async {
    if (!state.isPaused) return;
    final int seconds = _pausedRemaining > 0
        ? _pausedRemaining
        : state.remainingSeconds;
    if (seconds <= 0) {
      // Paused right on zero (for example by the notification button): resolve
      // the phase instead of parking the machine on a dead timer.
      state = state.copyWith(stage: FocusStage.running, remainingSeconds: 0);
      await _onTimerComplete();
      return;
    }
    final DateTime now = DateTime.now();
    state = state.copyWith(
      stage: FocusStage.running,
      remainingSeconds: seconds,
      endsAt: now.add(Duration(seconds: seconds)),
    );
    _startTicker();
    await _nativeResume(seconds);
    _persist();
  }

  /// "End": finish the current step now, record the real elapsed time and mark
  /// the step 100% complete (never a partial 50% write), then land on the
  /// completion screen where the next step can be started.
  Future<void> endStep() async {
    if (_busy || !(state.isRunning || state.isPaused)) return;
    _busy = true;
    try {
      _ticker?.cancel();
      final int recorded = _elapsedSeconds();
      final FocusPhase phase = state.phase;
      if (phase == FocusPhase.focus) {
        await _markCurrentStepComplete();
      }
      await _recordSession(completed: false, actualSeconds: recorded);
      _finish(FocusEndReason.ended, recorded);
    } finally {
      _busy = false;
    }
  }

  /// "Skip": leave the step untouched and move straight to the completion
  /// screen (which offers the next step).
  Future<void> skipStep() async {
    if (_busy || !(state.isRunning || state.isPaused)) return;
    _busy = true;
    try {
      _ticker?.cancel();
      final int recorded = _elapsedSeconds();
      await _recordSession(completed: false, actualSeconds: recorded);
      _finish(FocusEndReason.skipped, recorded);
    } finally {
      _busy = false;
    }
  }

  /// Starts the break immediately, for the notification action and the UI.
  Future<void> startBreakNow() async {
    if (_busy || !(state.isRunning || state.isPaused)) return;
    _busy = true;
    try {
      _ticker?.cancel();
      final int recorded = _elapsedSeconds();
      if (state.phase == FocusPhase.focus) {
        await _markCurrentStepComplete();
      }
      await _recordSession(completed: false, actualSeconds: recorded);
      await _beginBreak();
    } finally {
      _busy = false;
    }
  }

  /// Continues the linked task with the next step after a completion screen.
  Future<void> startNextStep() async {
    final FocusStepRef? next = state.nextStep;
    if (next == null || next.minutes <= 0) {
      reset();
      return;
    }
    final FocusTaskDraft draft = FocusTaskDraft(
      taskId: state.taskId ?? '',
      taskTitle: state.taskTitle ?? '',
      subjectName: state.subjectName,
      steps: state.steps,
      startIndex: state.stepIndex + 1,
    );
    await start(
      mode: FocusMode.linked,
      minutes: next.minutes,
      draft: draft,
    );
  }

  /// Leaves the completion screen and returns to the setup screen.
  ///
  /// The Today draft follows the session: a completed step advances it to the
  /// next one (or clears it when the task is done), while a skipped step leaves
  /// it untouched so it can be started again. This is what stops the setup
  /// screen from re-offering a step that is already 100%.
  void dismissFinished() {
    _ticker?.cancel();
    _busy = false;
    _pausedRemaining = 0;
    final bool linked = state.mode == FocusMode.linked;
    final bool stepDone =
        linked &&
        state.phase == FocusPhase.focus &&
        state.reason != FocusEndReason.skipped;
    final bool hasNext = state.nextStep != null;
    final FocusTaskDraft? nextDraft = stepDone && hasNext
        ? FocusTaskDraft(
            taskId: state.taskId ?? '',
            taskTitle: state.taskTitle ?? '',
            subjectName: state.subjectName,
            steps: state.steps,
            startIndex: state.stepIndex + 1,
          )
        : null;
    state = const FocusSessionState();
    if (stepDone) {
      ref.read(focusDraftProvider.notifier).state = nextDraft;
    }
    _persist();
  }

  /// Hard reset, also stopping the native timer.
  void reset() {
    _ticker?.cancel();
    _busy = false;
    _pausedRemaining = 0;
    state = const FocusSessionState();
    unawaited(_nativeStop());
    _persist();
  }

  /// Applies an action chosen from the notification while the app was closed.
  Future<void> consumePendingAction() async {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final String? action = prefs.getString(pendingActionKey);
      if (action == null || action.isEmpty) return;
      // Keep the action until a session exists; a cold start may still be
      // restoring the running session when this is first called.
      if (!(state.isRunning || state.isPaused)) return;
      await prefs.remove(pendingActionKey);
      switch (action) {
        case 'skip_step':
          await skipStep();
        case 'start_break':
          await startBreakNow();
      }
    } catch (_) {
      // A missing preference simply means there is nothing to consume.
    }
  }

  // ------------------------------------------------------------- transitions

  Future<void> _beginBreak() async {
    final int minutes = state.breakMinutes > 0 ? state.breakMinutes : 5;
    final DateTime now = DateTime.now();
    state = state.copyWith(
      stage: FocusStage.running,
      phase: FocusPhase.breakTime,
      plannedSeconds: minutes * 60,
      remainingSeconds: minutes * 60,
      startedAt: now,
      endsAt: now.add(Duration(minutes: minutes)),
    );
    _startTicker();
    await _nativeStart(phase: FocusPhase.breakTime, seconds: minutes * 60);
    _persist();
  }

  /// Guards against the ticker and the native mirror both reporting the end of
  /// the same phase.
  Future<void> _onTimerComplete() async {
    if (_busy || !state.isRunning) return;
    _busy = true;
    try {
      _ticker?.cancel();
      final FocusPhase phase = state.phase;
      final int planned = state.plannedSeconds;
      if (phase == FocusPhase.focus) {
        await _markCurrentStepComplete();
      }
      await _recordSession(completed: true, actualSeconds: planned);
      final bool wantsBreak =
          phase == FocusPhase.focus && state.autoBreak && state.breakMinutes > 0;
      if (wantsBreak) {
        await _beginBreak();
        return;
      }
      _finish(FocusEndReason.completed, planned);
    } finally {
      _busy = false;
    }
  }

  void _finish(FocusEndReason reason, int recorded) {
    _ticker?.cancel();
    unawaited(_nativeStop());
    state = state.finish(reason: reason, recordedSeconds: recorded);
    _persist();
  }

  // ------------------------------------------------------------------- timers

  void _startTicker() {
    _ticker?.cancel();
    int ticks = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!state.isRunning) return;
      final DateTime? endsAt = state.endsAt;
      if (endsAt == null) return;
      final int remaining = endsAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        state = state.copyWith(remainingSeconds: 0);
        unawaited(_onTimerComplete());
        return;
      }
      state = state.copyWith(remainingSeconds: remaining);
      ticks += 1;
      if (ticks % 5 == 0) {
        unawaited(_adoptNotificationPause());
      }
    });
  }

  /// The notification's Pause button drives the native service; adopting that
  /// here keeps the in-app UI in sync without polling every second.
  Future<void> _adoptNotificationPause() async {
    if (!state.isRunning) return;
    final Map<dynamic, dynamic> native = await _nativeGetState();
    if (native['paused'] != true) return;
    final int remainingMs = (native['remainingMs'] as num?)?.toInt() ?? 0;
    if (remainingMs > 0) {
      _pausedRemaining = (remainingMs / 1000).ceil();
    }
    if (state.isRunning) pause();
  }

  int _elapsedSeconds() {
    if (state.isPaused) {
      final int elapsed = state.plannedSeconds - _pausedRemaining;
      return elapsed.clamp(0, state.plannedSeconds);
    }
    final int elapsed = state.plannedSeconds - state.remainingSeconds;
    return elapsed.clamp(0, state.plannedSeconds);
  }

  // ----------------------------------------------------------------- persistence

  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final String? raw = prefs.getString(sessionKey);
      if (raw == null || raw.isEmpty) return;
      final FocusSessionState? saved = FocusSessionState.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
      if (saved == null) {
        await prefs.remove(sessionKey);
        return;
      }

      final Map<dynamic, dynamic> native = await _nativeGetState();
      final bool nativePaused = native['paused'] == true;
      final int nativeMs = (native['remainingMs'] as num?)?.toInt() ?? 0;

      if (nativeMs > 0) {
        final int seconds = (nativeMs / 1000).ceil();
        _pausedRemaining = seconds;
        state = saved.copyWith(
          stage: nativePaused ? FocusStage.paused : FocusStage.running,
          remainingSeconds: seconds,
          endsAt: DateTime.now().add(Duration(milliseconds: nativeMs)),
        );
        if (state.isRunning) _startTicker();
        _persist();
        unawaited(consumePendingAction());
        return;
      }

      // No native timer: either the user paused and the service died, or the
      // phase ran out while the app was gone.
      if (saved.isPaused && saved.remainingSeconds > 0) {
        _pausedRemaining = saved.remainingSeconds;
        state = saved.copyWith(
          stage: FocusStage.paused,
          remainingSeconds: saved.remainingSeconds,
        );
        _persist();
        unawaited(consumePendingAction());
        return;
      }

      state = saved.copyWith(
        stage: FocusStage.running,
        remainingSeconds: 0,
      );
      await _completeExpiredPhase();
    } catch (_) {
      state = const FocusSessionState();
    }
  }

  /// A phase that ended while the app was closed always resolves to the
  /// completion screen — never to a stuck "paused at 00:00" UI.
  Future<void> _completeExpiredPhase() async {
    if (_busy) return;
    _busy = true;
    try {
      final FocusPhase phase = state.phase;
      if (phase == FocusPhase.focus) {
        await _markCurrentStepComplete();
      }
      await _recordSession(
        completed: true,
        actualSeconds: state.plannedSeconds,
      );
      _finish(FocusEndReason.completed, state.plannedSeconds);
    } finally {
      _busy = false;
    }
  }

  void _persist() {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      if (!state.isRunning && !state.isPaused) {
        unawaited(prefs.remove(sessionKey));
        return;
      }
      unawaited(prefs.setString(sessionKey, jsonEncode(state.toJson())));
    } catch (_) {
      // Persistence is best-effort; the in-memory machine stays correct.
    }
  }

  // ------------------------------------------------------------------- effects

  Future<void> _markCurrentStepComplete() async {
    final FocusStepRef? step = state.currentStep;
    if (step == null) return;
    final UserStateRepository repo = ref.read(userStateRepositoryProvider);
    try {
      await repo.setStepCompleted(step.id, StepProgress.completed);
    } catch (_) {
      return;
    }
    // The task rolls up from its steps: only close it when this was the last
    // one, otherwise the card would read "complete" while steps remain.
    final String? taskId = state.taskId;
    if (taskId != null && state.nextStep == null) {
      try {
        await repo.setTaskStatus(taskId, 'completed');
      } catch (_) {}
    }
  }

  Future<void> _markTaskInProgress() async {
    final String? taskId = state.taskId;
    if (taskId == null) return;
    try {
      await ref
          .read(userStateRepositoryProvider)
          .setTaskStatus(taskId, 'in_progress');
    } catch (_) {}
  }

  Future<void> _recordSession({
    required bool completed,
    required int actualSeconds,
  }) async {
    final DateTime? startedAt = state.startedAt;
    if (startedAt == null) return;
    try {
      final AppDatabase db = ref.read(appDatabaseProvider);
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              taskId: Value<String?>(state.taskId),
              stepId: Value<String?>(state.currentStep?.id),
              phase: state.phase.wire,
              plannedSeconds: state.plannedSeconds,
              actualSeconds: actualSeconds.clamp(0, state.plannedSeconds),
              startedAt: startedAt,
              endedAt: Value<DateTime>(DateTime.now()),
              completed: Value<bool>(completed),
            ),
          );
    } catch (_) {
      // Analytics must never block the user's session.
    }
  }

  // -------------------------------------------------------------------- native

  Future<void> _nativeStart({
    required FocusPhase phase,
    required int seconds,
  }) async {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      await _channel.invokeMethod<void>('start', <String, dynamic>{
        'durationMs': seconds * 1000,
        'taskId': state.taskId,
        'stepId': state.currentStep?.id,
        'phase': phase.wire,
        'taskTitle': state.taskTitle,
        'hasNextStep': state.hasNextStep,
        'breakEnabled': state.autoBreak && state.breakMinutes > 0,
        'breakMinutes': state.breakMinutes > 0 ? state.breakMinutes : 5,
        'notificationsEnabled':
            prefs.getBool('notif_timer_enabled') ?? true,
      });
    } catch (_) {
      // No foreground service (for example a desktop test): the in-app ticker
      // still runs the session.
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
}

final NotifierProvider<FocusController, FocusSessionState>
focusControllerProvider =
    NotifierProvider<FocusController, FocusSessionState>(FocusController.new);

/// User-controlled immersive mode. Watched by the shell so the bottom
/// navigation bar only disappears when the user asks for full screen.
final StateProvider<bool> focusImmersiveProvider = StateProvider<bool>(
  (Ref ref) => false,
);

/// The plan task Today hands to the setup screen, if any.
final StateProvider<FocusTaskDraft?> focusDraftProvider =
    StateProvider<FocusTaskDraft?>((Ref ref) => null);
