import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/services.dart' show EventChannel, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/focus_notifications.dart';
import '../../../core/settings/notification_prefs.dart';
import '../../../core/sound/sound_effects.dart';
import '../../../core/settings/theme_mode_controller.dart'
    show sharedPreferencesProvider;
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/sync_queue_repository.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../data/sync/sync_ids.dart';
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
    this.focusMinutes = 25,
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
  final int focusMinutes;
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

  FocusStepRef? get nextStep => steps.isEmpty || stepIndex + 1 >= steps.length
      ? null
      : steps[stepIndex + 1];

  bool get hasNextStep => nextStep != null;

  /// 1 → full arc (just started), 0 → empty arc.
  ///
  /// Free mode counts up, so the ring rotates once per hour.
  double get progress {
    if (mode == FocusMode.free) {
      final int cycle = remainingSeconds % 3600;
      return cycle / 3600.0;
    }
    if (plannedSeconds <= 0) return 0;
    final double elapsed = (plannedSeconds - remainingSeconds) / plannedSeconds;
    return elapsed.clamp(0.0, 1.0);
  }

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
    int? focusMinutes,
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
      focusMinutes: focusMinutes ?? this.focusMinutes,
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
      focusMinutes: focusMinutes,
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
    'focusMinutes': focusMinutes,
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
      focusMinutes: intOf(json['focusMinutes'], 25),
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

  /// Real-time pushes from the Kotlin foreground service ("end", "pause",
  /// "resume", "skip_step", "start_break"). Without it, notification buttons
  /// tapped while the app is already open only wrote a preference that nobody
  /// read until the next resume.
  static const EventChannel _events = EventChannel('khutati/focus_events');
  static const String sessionKey = 'focus_session_v2';
  static const String pendingActionKey = 'pending_focus_action';

  StreamSubscription<dynamic>? _nativeEvents;
  Timer? _ticker;
  bool _restored = false;
  bool _restoring = false;
  bool _busy = false;
  int _pausedRemaining = 0;

  @override
  FocusSessionState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      unawaited(_nativeEvents?.cancel());
      _nativeEvents = null;
    });
    _nativeEvents = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object _) {},
    );
    Future<void>.microtask(_restore);
    return const FocusSessionState();
  }

  // ---------------------------------------------------------------- lifecycle

  /// Starts an idle-state session. [draft] is only meaningful for
  /// [FocusMode.linked]; [FocusMode.free] counts up instead of down.
  Future<void> start({
    required FocusMode mode,
    required int minutes,
    int breakMinutes = 0,
    bool autoBreak = false,
    FocusTaskDraft? draft,
  }) async {
    if (minutes <= 0 && mode != FocusMode.free) return;
    _ticker?.cancel();
    _busy = false;
    _pausedRemaining = 0;

    final DateTime now = DateTime.now();
    final bool free = mode == FocusMode.free;
    // Enforce the 5-minute floor for every countdown mode, including linked
    // task steps whose plan may have been authored with shorter steps.
    final int safeMinutes = free
        ? 0
        : minutes.clamp(FocusSetup.minMinutes, FocusSetup.maxMinutes);
    final int seconds = free ? 0 : safeMinutes * 60;
    state = FocusSessionState(
      stage: FocusStage.running,
      phase: FocusPhase.focus,
      mode: mode,
      taskId: draft?.taskId,
      taskTitle: draft?.taskTitle,
      subjectName: draft?.subjectName,
      steps: draft?.steps ?? const <FocusStepRef>[],
      stepIndex: draft?.startIndex ?? 0,
      plannedSeconds: free ? 3600 : seconds,
      remainingSeconds: free ? 0 : seconds,
      startedAt: now,
      endsAt: free ? null : now.add(Duration(seconds: seconds)),
      breakMinutes: breakMinutes,
      focusMinutes: safeMinutes,
      autoBreak: autoBreak,
    );
    _startTicker();
    if (!free) {
      await _nativeStart(phase: FocusPhase.focus, seconds: seconds);
    }
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
    if (state.mode == FocusMode.free) {
      state = state.copyWith(stage: FocusStage.running);
      _startTicker();
      _persist();
      return;
    }
    final int seconds = _pausedRemaining > 0
        ? _pausedRemaining
        : state.remainingSeconds;
    if (seconds <= 0) {
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
  /// the step 100% complete (never a partial 50% write).
  ///
  /// If the task has a next step, transition straight to it (resetting the
  /// timer) instead of showing the completion screen. Only the last step lands
  /// on the completion screen.
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

      if (state.mode == FocusMode.linked && state.hasNextStep) {
        final FocusStepRef? next = state.nextStep;
        if (next != null && next.minutes > 0) {
          final DateTime now = DateTime.now();
          final int seconds =
              next.minutes.clamp(FocusSetup.minMinutes, FocusSetup.maxMinutes) *
              60;
          state = state.copyWith(
            stepIndex: state.stepIndex + 1,
            plannedSeconds: seconds,
            remainingSeconds: seconds,
            startedAt: now,
            endsAt: now.add(Duration(seconds: seconds)),
            stage: FocusStage.running,
            phase: FocusPhase.focus,
            recordedSeconds: 0,
          );
          _startTicker();
          await _nativeStart(phase: FocusPhase.focus, seconds: seconds);
          _persist();
          return;
        }
      }

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
    await start(mode: FocusMode.linked, minutes: next.minutes, draft: draft);
  }

  /// "Skip": leave the current item untouched and move on.
  ///
  /// Skip is deliberately *not* a completion. It never calls
  /// [_markCurrentStepComplete] and never writes a `completed` task status, so
  /// a skipped step keeps whatever progress it already had (0% or 50%) and the
  /// task card does not jump to 100%. Only [endStep] and a real expiry mark a
  /// step done.
  Future<void> skipPhase() async {
    if (_busy || !state.isRunning) return;
    _busy = true;
    try {
      _ticker?.cancel();
      final int recorded = _elapsedSeconds();
      await _recordSession(completed: false, actualSeconds: recorded);

      if (state.mode == FocusMode.linked) {
        final FocusStepRef? next = state.nextStep;
        if (next == null || next.minutes <= 0) {
          // Nothing left to move to: park on the skipped screen instead of
          // leaving a dead 00:00 timer running on the last step.
          _finish(FocusEndReason.skipped, recorded);
          return;
        }
        final DateTime now = DateTime.now();
        final int seconds =
            next.minutes.clamp(FocusSetup.minMinutes, FocusSetup.maxMinutes) *
            60;
        state = state.copyWith(
          stepIndex: state.stepIndex + 1,
          plannedSeconds: seconds,
          remainingSeconds: seconds,
          startedAt: now,
          endsAt: now.add(Duration(seconds: seconds)),
          stage: FocusStage.running,
          phase: FocusPhase.focus,
          recordedSeconds: 0,
        );
        _startTicker();
        await _nativeStart(phase: FocusPhase.focus, seconds: seconds);
        _persist();
        return;
      }

      if (state.mode == FocusMode.pomodoro &&
          state.phase == FocusPhase.focus &&
          state.breakMinutes > 0) {
        await _beginBreak();
        return;
      }
      if (state.mode == FocusMode.pomodoro && state.isBreak) {
        // Break -> next focus round.
        final int minutes = state.focusMinutes > 0 ? state.focusMinutes : 25;
        final DateTime now = DateTime.now();
        state = state.copyWith(
          stage: FocusStage.running,
          phase: FocusPhase.focus,
          plannedSeconds: minutes * 60,
          remainingSeconds: minutes * 60,
          startedAt: now,
          endsAt: now.add(Duration(minutes: minutes)),
          rounds: state.rounds + 1,
          recordedSeconds: 0,
        );
        _startTicker();
        await _nativeStart(phase: FocusPhase.focus, seconds: minutes * 60);
        _persist();
        return;
      }

      // Pomodoro with no break, or any other phase: end without completing.
      _finish(FocusEndReason.skipped, recorded);
    } finally {
      _busy = false;
    }
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
  ///
  /// Only the explicit notification buttons write an action. Tapping the body
  /// of the notification writes nothing at all, so opening the app from the
  /// shade can never end a session. A queued action that outlives its session
  /// is discarded instead of being applied to the next one.
  Future<void> consumePendingAction() async {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final String? action = prefs.getString(pendingActionKey);
      if (action == null || action.isEmpty) return;
      // A cold start may still be restoring the running session; leave the
      // action queued until there is a state to apply it to.
      if (_restoring) return;
      if (!(state.isRunning || state.isPaused)) {
        await prefs.remove(pendingActionKey);
        return;
      }
      await prefs.remove(pendingActionKey);
      switch (action) {
        case 'skip_step':
          await skipPhase();
        case 'start_break':
          await startBreakNow();
        case 'end':
          await endStep();
      }
    } catch (_) {
      // A missing preference simply means there is nothing to consume.
    }
  }

  /// Notification actions pushed while the app is alive.
  ///
  /// This is the foreground half of the sync: Kotlin owns the notification, so
  /// the moment the user taps End/Pause/Resume the native side pushes the event
  /// and this handler mutates the in-app state immediately. A killed process
  /// still goes through [consumePendingAction].
  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final Object? event = raw['event'];

    switch (event) {
      case 'end':
        if (_busy || !(state.isRunning || state.isPaused)) return;
        unawaited(_applyLiveAction('end', endStep));
      case 'pause':
        if (!state.isRunning) return;
        final int ms = (raw['remainingMs'] as num?)?.toInt() ?? 0;
        _ticker?.cancel();
        _pausedRemaining = ms > 0 ? (ms / 1000).ceil() : state.remainingSeconds;
        state = state.copyWith(
          stage: FocusStage.paused,
          remainingSeconds: _pausedRemaining,
        );
        _persist();
      case 'resume':
        if (!state.isPaused) return;
        final int ms = (raw['remainingMs'] as num?)?.toInt() ?? 0;
        final int seconds = ms > 0 ? (ms / 1000).ceil() : _pausedRemaining;
        if (seconds <= 0) return;
        final DateTime now = DateTime.now();
        _pausedRemaining = seconds;
        state = state.copyWith(
          stage: FocusStage.running,
          remainingSeconds: seconds,
          endsAt: now.add(Duration(seconds: seconds)),
        );
        _startTicker();
        _persist();
      case 'skip_step':
        if (_busy || !(state.isRunning || state.isPaused)) return;
        unawaited(_applyLiveAction('skip_step', skipPhase));
      case 'start_break':
        if (_busy || !(state.isRunning || state.isPaused)) return;
        unawaited(_applyLiveAction('start_break', startBreakNow));
    }
  }

  /// Runs a notification action and drops the matching cold-start fallback.
  ///
  /// Kotlin also writes the persisted fallback for "end" (a killed process
  /// never receives the push), so the live path drops it before applying —
  /// replaying "end" a second time would advance two steps.
  Future<void> _applyLiveAction(
    String action,
    Future<void> Function() apply,
  ) async {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      if (prefs.getString(pendingActionKey) == action) {
        await prefs.remove(pendingActionKey);
      }
    } catch (_) {}
    await apply();
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
    if (state.mode == FocusMode.free) return;
    if (_busy || !state.isRunning) return;
    await _notifyTimerComplete(state.phase);
    _busy = true;
    try {
      _ticker?.cancel();
      final FocusPhase phase = state.phase;
      final int planned = state.plannedSeconds;
      if (phase == FocusPhase.focus) {
        await _markCurrentStepComplete();
      }
      await _recordSession(completed: true, actualSeconds: planned);

      // Linked task with a following step: advance automatically instead of
      // finishing, so the next step starts without a completion dialog.
      if (state.mode == FocusMode.linked && state.hasNextStep) {
        final FocusStepRef? next = state.nextStep;
        if (next != null && next.minutes > 0) {
          final DateTime now = DateTime.now();
          final int seconds =
              next.minutes.clamp(FocusSetup.minMinutes, FocusSetup.maxMinutes) *
              60;
          state = state.copyWith(
            stepIndex: state.stepIndex + 1,
            plannedSeconds: seconds,
            remainingSeconds: seconds,
            startedAt: now,
            endsAt: now.add(Duration(seconds: seconds)),
            stage: FocusStage.running,
            phase: FocusPhase.focus,
            recordedSeconds: 0,
          );
          _startTicker();
          await _nativeStart(phase: FocusPhase.focus, seconds: seconds);
          _persist();
          _busy = false;
          return;
        }
      }

      final bool wantsBreak =
          phase == FocusPhase.focus &&
          state.autoBreak &&
          state.breakMinutes > 0;
      if (wantsBreak) {
        await _beginBreak();
        return;
      }
      // Pomodoro break -> next focus round (seamless, mirrors the HTML).
      if (state.mode == FocusMode.pomodoro &&
          phase == FocusPhase.breakTime &&
          state.autoBreak) {
        final int minutes = state.focusMinutes > 0 ? state.focusMinutes : 25;
        final DateTime now = DateTime.now();
        state = state.copyWith(
          stage: FocusStage.running,
          phase: FocusPhase.focus,
          plannedSeconds: minutes * 60,
          remainingSeconds: minutes * 60,
          startedAt: now,
          endsAt: now.add(Duration(minutes: minutes)),
          rounds: state.rounds + 1,
        );
        _startTicker();
        await _nativeStart(phase: FocusPhase.focus, seconds: minutes * 60);
        _persist();
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
    if (state.mode == FocusMode.free) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
        if (!state.isRunning) return;
        state = state.copyWith(remainingSeconds: state.remainingSeconds + 1);
      });
      return;
    }
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
    });
  }

  /// Reconciles the in-app machine with the Kotlin foreground service.
  ///
  /// Called when the app comes back to the foreground and after a cold-start
  /// restore. Two rules make it safe:
  ///
  /// * The deadline is absolute. The service's persisted `targetEndMs` wins;
  ///   if the service has no timer at all, the session's own persisted
  ///   `endsAt` is used. A *missing* service is never treated as an ending.
  /// * A phase completes only when a real deadline is in the past, and it
  ///   completes through [_onTimerComplete] (the natural-expiry path).
  ///   [endStep] — the manual "End" that marks the step done and jumps to the
  ///   next one — is unreachable from lifecycle reconciliation. That is the
  ///   fix for "opening the app from the notification ends my task".
  Future<void> syncWithNative() async {
    if (!(state.isRunning || state.isPaused)) return;
    final Map<dynamic, dynamic> native = await _nativeGetState();

    final bool nativePaused = native['paused'] == true;
    final int targetEndMs = (native['targetEndMs'] as num?)?.toInt() ?? 0;
    final FocusPhase nativePhase = FocusPhase.parse(native['phase'] as String?);
    final int nativePlannedSeconds =
        (native['plannedSeconds'] as num?)?.toInt() ?? 0;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    // A native pause wins before any deadline math. Pausing from the
    // notification zeroes `targetEndMs`, so the in-app `endsAt` is stale the
    // moment it happens: treating it as the deadline made a paused session look
    // expired and complete itself as soon as the app came back.
    if (nativePaused) {
      final int pausedMs = (native['remainingMs'] as num?)?.toInt() ?? 0;
      final int pausedSeconds = pausedMs > 0
          ? (pausedMs / 1000).ceil()
          : (state.isPaused ? _pausedRemaining : state.remainingSeconds);
      _ticker?.cancel();
      _pausedRemaining = pausedSeconds;
      state = state.copyWith(
        stage: FocusStage.paused,
        remainingSeconds: pausedSeconds,
      );
      _persist();
      return;
    }

    // No absolute deadline: a free (count-up) session, or a session whose
    // service is gone. Never invent an ending from a missing service.
    final int deadline = targetEndMs > 0
        ? targetEndMs
        : (state.isRunning ? (state.endsAt?.millisecondsSinceEpoch ?? 0) : 0);

    if (deadline <= 0) {
      if (state.isRunning &&
          state.mode != FocusMode.free &&
          state.remainingSeconds > 0) {
        // The service was killed (or never started) while a countdown is still
        // running here. Re-arm it so the background alert is not silently
        // lost, then pick the new deadline up on the next reconcile.
        await _nativeStart(phase: state.phase, seconds: state.remainingSeconds);
        return;
      }
      return;
    }

    final int remainingMs = deadline - nowMs;

    // Genuinely expired while we were away: same path as a 00:00 tick.
    if (remainingMs <= 0) {
      if (!state.isRunning) return; // a paused session stays paused
      state = state.copyWith(remainingSeconds: 0);
      await _onTimerComplete();
      return;
    }

    final int seconds = (remainingMs / 1000).ceil();

    // Native is running: resume from the exact remaining time.
    _pausedRemaining = seconds;
    if (state.isPaused) {
      if (nativePhase != state.phase) {
        await _adoptNativePhase(nativePhase);
      }
      state = state.copyWith(
        stage: FocusStage.running,
        phase: nativePhase,
        plannedSeconds: nativePlannedSeconds > 0
            ? nativePlannedSeconds
            : state.plannedSeconds,
        remainingSeconds: seconds,
        endsAt: DateTime.now().add(Duration(milliseconds: remainingMs)),
      );
      _startTicker();
      _persist();
      return;
    }

    // Both running. The service may have moved to the next phase (a break, or
    // the next Pomodoro round) while the Dart isolate was frozen; adopt it.
    if (nativePhase != state.phase) {
      await _adoptNativePhase(nativePhase);
    }
    state = state.copyWith(
      phase: nativePhase,
      plannedSeconds: nativePlannedSeconds > 0
          ? nativePlannedSeconds
          : state.plannedSeconds,
      remainingSeconds: seconds,
      endsAt: DateTime.now().add(Duration(milliseconds: remainingMs)),
    );
  }

  /// The service advanced a phase while Dart was frozen. Book the phase that
  /// just finished (step progress, session record, round count) before the
  /// caller swaps in the new phase, so a background session is never lost.
  Future<void> _adoptNativePhase(FocusPhase nativePhase) async {
    if (state.phase == FocusPhase.focus) {
      await _markCurrentStepComplete();
      await _recordSession(
        completed: true,
        actualSeconds: state.plannedSeconds,
      );
      state = state.copyWith(rounds: state.rounds + 1);
      return;
    }
    if (state.phase == FocusPhase.breakTime &&
        nativePhase == FocusPhase.focus &&
        state.mode == FocusMode.pomodoro) {
      state = state.copyWith(rounds: state.rounds + 1);
    }
  }

  int _elapsedSeconds() {
    if (state.mode == FocusMode.free) {
      return state.remainingSeconds;
    }
    if (state.isPaused) {
      final int elapsed = state.plannedSeconds - _pausedRemaining;
      return elapsed.clamp(0, state.plannedSeconds);
    }
    final int elapsed = state.plannedSeconds - state.remainingSeconds;
    return elapsed.clamp(0, state.plannedSeconds);
  }

  // ----------------------------------------------------------------- persistence

  Future<void> _restore() async {
    if (_restored || _restoring) return;
    _restoring = true;
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
      final int targetEndMs = (native['targetEndMs'] as num?)?.toInt() ?? 0;
      final int nativeRemainingMs =
          (native['remainingMs'] as num?)?.toInt() ?? 0;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;

      // Rule 1: a pause always wins. A paused session can never "expire".
      if (nativePaused) {
        final int seconds = (nativeRemainingMs / 1000).ceil();
        _pausedRemaining = seconds > 0 ? seconds : saved.remainingSeconds;
        state = saved.copyWith(
          stage: FocusStage.paused,
          remainingSeconds: _pausedRemaining,
        );
        _persist();
        return;
      }
      if (saved.isPaused) {
        _pausedRemaining = saved.remainingSeconds;
        state = saved.copyWith(
          stage: FocusStage.paused,
          remainingSeconds: saved.remainingSeconds,
        );
        _persist();
        return;
      }

      // Rule 2: the deadline is absolute — the service's `targetEndMs` first,
      // then our own persisted `endsAt`. Never a relative remaining value.
      final int deadline = targetEndMs > 0
          ? targetEndMs
          : (saved.endsAt?.millisecondsSinceEpoch ?? 0);

      if (deadline <= 0) {
        // No deadline anywhere: a count-up session, or a countdown whose
        // service never started. Park it paused with the last known value
        // instead of guessing that it finished.
        if (saved.mode == FocusMode.free || saved.remainingSeconds > 0) {
          _pausedRemaining = saved.remainingSeconds;
          state = saved.copyWith(
            stage: FocusStage.paused,
            remainingSeconds: saved.remainingSeconds,
          );
          _persist();
          return;
        }
        state = const FocusSessionState();
        await prefs.remove(sessionKey);
        return;
      }

      final int remainingMs = deadline - nowMs;
      if (remainingMs > 0) {
        // The service may have advanced to the next phase while the app was
        // closed; if it did, record the phase that just finished.
        final FocusPhase nativePhase = FocusPhase.parse(
          native['phase'] as String?,
        );
        if (nativePhase != saved.phase && saved.phase == FocusPhase.focus) {
          state = saved;
          await _markCurrentStepComplete();
          await _recordSession(
            completed: true,
            actualSeconds: saved.plannedSeconds,
          );
        }
        // Still running: resume from the exact remaining time.
        final int seconds = (remainingMs / 1000).ceil();
        _pausedRemaining = seconds;
        state = saved.copyWith(
          stage: FocusStage.running,
          phase: nativePhase,
          plannedSeconds:
              (native['plannedSeconds'] as num?)?.toInt() ??
              saved.plannedSeconds,
          remainingSeconds: seconds,
          endsAt: DateTime.now().add(Duration(milliseconds: remainingMs)),
        );
        _startTicker();
        _persist();
        return;
      }

      // The deadline really did pass while the app was closed.
      state = saved.copyWith(stage: FocusStage.running, remainingSeconds: 0);
      await _completeExpiredPhase();
    } catch (_) {
      state = const FocusSessionState();
    } finally {
      _restoring = false;
      _restored = true;
      unawaited(consumePendingAction());
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

  /// Fires at 00:00, before any transition work, so the alert is not delayed by
  /// database writes. The Kotlin service posts the same alert independently:
  /// when the Dart isolate is frozen in the background the native side is the
  /// only thing still running, and the user must still hear the timer end.
  Future<void> _notifyTimerComplete(FocusPhase phase) async {
    // The in-app chime follows the sound-effects toggle, independently of the
    // notification channel: a user can want a silent system alert but still
    // hear the completion inside the open app.
    if (phase == FocusPhase.focus) SoundEffects.success();
    if (!ref.read(notificationPrefsProvider).timer) return;
    await FocusNotifications.showCompletion(
      isBreak: phase == FocusPhase.breakTime,
    );
  }

  Future<void> _recordSession({
    required bool completed,
    required int actualSeconds,
  }) async {
    final DateTime? startedAt = state.startedAt;
    if (startedAt == null) return;
    try {
      final AppDatabase db = ref.read(appDatabaseProvider);
      final String clientId = SyncIds.newId();
      final DateTime endedAt = DateTime.now();
      final int recorded = state.mode == FocusMode.free
          ? actualSeconds
          : actualSeconds.clamp(0, state.plannedSeconds);
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              clientId: Value<String>(clientId),
              taskId: Value<String?>(state.taskId),
              taskTitle: Value<String?>(state.taskTitle),
              mode: Value<String>(state.mode.name),
              stepId: Value<String?>(state.currentStep?.id),
              phase: state.phase.wire,
              plannedSeconds: state.plannedSeconds,
              actualSeconds: recorded,
              startedAt: startedAt,
              endedAt: Value<DateTime>(endedAt),
              completed: Value<bool>(completed),
            ),
          );
      // Local write first, then the durable outbox. Sync may happen minutes
      // later (or after the next launch) without ever blocking the timer.
      await SyncQueueRepository(db).enqueue(
        'focus_session',
        clientId,
        <String, Object?>{
          'id': clientId,
          'task_id': state.taskId,
          'task_title': state.taskTitle,
          'mode': state.mode.name,
          'step_id': state.currentStep?.id,
          'phase': state.phase.wire,
          'planned_seconds': state.plannedSeconds,
          'actual_seconds': recorded,
          'started_at': isoOrNull(startedAt),
          'ended_at': isoOrNull(endedAt),
          'completed': completed,
          'updated_at': isoOrNull(endedAt),
        },
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
      await _channel.invokeMethod<void>('start', <String, dynamic>{
        'durationMs': seconds * 1000,
        'taskId': state.taskId,
        'stepId': state.currentStep?.id,
        'phase': phase.wire,
        'taskTitle': state.taskTitle,
        'hasNextStep': state.hasNextStep,
        'breakEnabled': state.autoBreak && state.breakMinutes > 0,
        'breakMinutes': state.breakMinutes > 0 ? state.breakMinutes : 5,
        // The real preference key (`notif_timer`), read through its controller
        // so the native service honours a toggle changed mid-session.
        'notificationsEnabled': ref.read(notificationPrefsProvider).timer,
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
focusControllerProvider = NotifierProvider<FocusController, FocusSessionState>(
  FocusController.new,
);

/// User-controlled immersive mode. Watched by the shell so the bottom
/// navigation bar only disappears when the user asks for full screen.
final StateProvider<bool> focusImmersiveProvider = StateProvider<bool>(
  (Ref ref) => false,
);

/// The plan task Today hands to the setup screen, if any.
final StateProvider<FocusTaskDraft?> focusDraftProvider =
    StateProvider<FocusTaskDraft?>((Ref ref) => null);

/// Live stream of recorded focus sessions, newest first, for the history sheet.
final StreamProvider<List<FocusSession>> focusHistoryProvider =
    StreamProvider<List<FocusSession>>((Ref ref) {
      final AppDatabase db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.focusSessions,
      )..orderBy([(t) => OrderingTerm.desc(t.startedAt)])).watch();
    });
