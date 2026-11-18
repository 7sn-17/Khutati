/// Focus-domain value objects: the timer modes offered on the setup screen,
/// the session phase, and the lifecycle stage of the focus state machine.
///
/// Kept pure (no Flutter, no Drift) so the state machine can be reasoned about
/// in isolation and the UI only renders what it exposes.
library;

/// What kind of session the user is configuring.
enum FocusMode {
  /// Follows a concrete plan step (attendance → study → questions).
  linked,

  /// Classic focus/break cycle.
  pomodoro,

  /// A single countdown the user sets by hand.
  free,
}

/// Pomodoro presets offered before a session starts.
enum PomodoroPreset {
  classic(focusMinutes: 25, breakMinutes: 5),
  deep(focusMinutes: 50, breakMinutes: 10),
  custom(focusMinutes: 25, breakMinutes: 5);

  const PomodoroPreset({
    required this.focusMinutes,
    required this.breakMinutes,
  });

  final int focusMinutes;
  final int breakMinutes;

  static PomodoroPreset parse(String? raw) {
    for (final PomodoroPreset preset in values) {
      if (preset.name == raw) return preset;
    }
    return PomodoroPreset.classic;
  }
}

/// Phase of the running timer. The `wire` value is what the Kotlin service and
/// the `focus_sessions.phase` column store.
enum FocusPhase {
  focus('focus'),
  breakTime('break');

  const FocusPhase(this.wire);

  final String wire;

  bool get isBreak => this == FocusPhase.breakTime;

  static FocusPhase parse(String? raw) {
    if (raw == FocusPhase.breakTime.wire) return FocusPhase.breakTime;
    return FocusPhase.focus;
  }
}

/// Lifecycle stage of the focus state machine.
///
/// The machine only ever moves through these edges:
/// idle → running ⇄ paused → finished → idle
/// Breaks, skipped steps and restored sessions are expressed through
/// [FocusPhase] and [FocusEndReason], never by parking the UI in a half-state.
enum FocusStage { idle, running, paused, finished }

/// Why the current session left the running stage.
enum FocusEndReason {
  /// The timer reached zero.
  completed,

  /// The user pressed "End"; the step is recorded as 100% done.
  ended,

  /// The user pressed "Skip"; the step is left untouched.
  skipped,
}

/// One plan step in the shape the focus machine needs. Carrying the whole
/// remaining chain keeps "next step" correct even for three-step tasks.
class FocusStepRef {
  const FocusStepRef({
    required this.id,
    required this.label,
    required this.minutes,
  });

  final String id;

  /// Localised kind ("حضور", "دراسة", "حل الأسئلة").
  final String label;
  final int minutes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'minutes': minutes,
  };

  static FocusStepRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String? id = raw['id'] as String?;
    if (id == null || id.isEmpty) return null;
    return FocusStepRef(
      id: id,
      label: (raw['label'] as String?) ?? '',
      minutes: (raw['minutes'] as num?)?.toInt() ?? 0,
    );
  }

  static List<FocusStepRef> listFromJson(Object? raw) {
    if (raw is! List) return const <FocusStepRef>[];
    final List<FocusStepRef> steps = <FocusStepRef>[];
    for (final Object? entry in raw) {
      final FocusStepRef? step = FocusStepRef.fromJson(entry);
      if (step != null) steps.add(step);
    }
    return List<FocusStepRef>.unmodifiable(steps);
  }
}

/// The plan task a linked session follows, prepared by Today.
class FocusTaskDraft {
  const FocusTaskDraft({
    required this.taskId,
    required this.taskTitle,
    required this.steps,
    this.subjectName,
    this.startIndex = 0,
  });

  final String taskId;
  final String taskTitle;
  final String? subjectName;
  final List<FocusStepRef> steps;
  final int startIndex;

  FocusStepRef? get current =>
      steps.isEmpty ? null : steps[startIndex.clamp(0, steps.length - 1)];

  FocusStepRef? get next =>
      steps.isEmpty || startIndex + 1 >= steps.length
      ? null
      : steps[startIndex + 1];

  int get minutes => current?.minutes ?? 0;

  /// Identity so the setup screen can tell two drafts apart.
  String get key => '$taskId:${current?.id ?? '-'}';
}

/// Persisted setup choices, so reopening the tab lands on the same mode.
class FocusSetup {
  const FocusSetup({
    this.mode = FocusMode.pomodoro,
    this.preset = PomodoroPreset.classic,
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.autoBreak = true,
    this.freeMinutes = 25,
  });

  final FocusMode mode;
  final PomodoroPreset preset;
  final int focusMinutes;
  final int breakMinutes;
  final bool autoBreak;

  /// Manual length used by [FocusMode.free].
  final int freeMinutes;

  static const int minMinutes = 5;
  static const int maxMinutes = 180;

  /// How long the focus phase should run for the selected manual mode.
  int get startMinutes =>
      mode == FocusMode.free ? freeMinutes : focusMinutes;

  FocusSetup copyWith({
    FocusMode? mode,
    PomodoroPreset? preset,
    int? focusMinutes,
    int? breakMinutes,
    bool? autoBreak,
    int? freeMinutes,
  }) {
    return FocusSetup(
      mode: mode ?? this.mode,
      preset: preset ?? this.preset,
      focusMinutes: focusMinutes ?? this.focusMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      autoBreak: autoBreak ?? this.autoBreak,
      freeMinutes: freeMinutes ?? this.freeMinutes,
    );
  }

  FocusSetup withPreset(PomodoroPreset next) {
    if (next == PomodoroPreset.custom) {
      return copyWith(preset: next);
    }
    return copyWith(
      preset: next,
      focusMinutes: next.focusMinutes,
      breakMinutes: next.breakMinutes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mode': mode.name,
    'preset': preset.name,
    'focusMinutes': focusMinutes,
    'breakMinutes': breakMinutes,
    'autoBreak': autoBreak,
    'freeMinutes': freeMinutes,
  };

  static FocusSetup fromJson(Map<String, dynamic> json, FocusSetup fallback) {
    FocusMode mode = fallback.mode;
    for (final FocusMode value in FocusMode.values) {
      if (value.name == json['mode']) mode = value;
    }
    int clamp(Object? raw, int fallbackValue) {
      final int value = (raw as num?)?.toInt() ?? fallbackValue;
      return value.clamp(minMinutes, maxMinutes);
    }

    return FocusSetup(
      mode: mode,
      preset: PomodoroPreset.parse(json['preset'] as String?),
      focusMinutes: clamp(json['focusMinutes'], fallback.focusMinutes),
      breakMinutes: clamp(json['breakMinutes'], fallback.breakMinutes),
      autoBreak: json['autoBreak'] != false,
      freeMinutes: clamp(json['freeMinutes'], fallback.freeMinutes),
    );
  }
}
