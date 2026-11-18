import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// Template tables — the imported 68-day plan.
//
// These are written exactly once per dataset version (Phase 2.1) and are never
// mutated afterwards. User edits live in the user tables below as overrides, so
// "restore to default" is always possible (PRD section 6.1).
// ---------------------------------------------------------------------------

@DataClassName('PlanRow')
class Plans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get datasetVersion => integer()();
  DateTimeColumn get startDate => dateTime()();
  IntColumn get totalDays => integer()();
  IntColumn get studyDays => integer()();
  IntColumn get totalPlannedMinutes => integer()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

@DataClassName('SubjectRow')
class Subjects extends Table {
  TextColumn get id => text()();

  /// Dataset key, e.g. `chem`, `phys`, `bio`, `hist`, `eng`.
  TextColumn get key => text()();
  TextColumn get nameAr => text()();
  TextColumn get instructor => text()();
  TextColumn get accentHex => text()();
  IntColumn get sortOrder => integer()();

  // Page-2 totals, kept for reconciliation against the PDF.
  IntColumn get attendanceMinutes => integer().withDefault(const Constant(0))();
  IntColumn get studyMinutes => integer().withDefault(const Constant(0))();
  IntColumn get courseMinutes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

@DataClassName('ChapterRow')
class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get title => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

@DataClassName('LessonRow')
class Lessons extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get chapterId => text().nullable().references(Chapters, #id)();
  TextColumn get title => text()();

  /// `foundation` or `lecture` (PRD section 3, time accounting rules).
  TextColumn get kind => text()();
  IntColumn get attendanceMinutes => integer()();
  IntColumn get studyMinutes => integer()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

@DataClassName('DayRow')
class Days extends Table {
  TextColumn get id => text()();
  IntColumn get dayNumber => integer().unique()();
  IntColumn get week => integer()();

  /// `normal`, `practical` or `rest`.
  TextColumn get type => text()();
  IntColumn get statedStudyMinutes => integer().withDefault(const Constant(0))();
  TextColumn get startClock => text().nullable()();
  TextColumn get endClock => text().nullable()();
  TextColumn get headerTitle => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get dayId => text().references(Days, #id)();
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get chapterId => text().nullable().references(Chapters, #id)();
  TextColumn get title => text()();

  /// `foundation`, `lecture` or `course_questions`.
  TextColumn get type => text()();

  /// The PDF "group" heading (chapter name). `group` is a SQL keyword.
  TextColumn get groupTitle => text().nullable()();
  IntColumn get sortOrder => integer()();
  TextColumn get suggestedStart => text().nullable()();
  TextColumn get suggestedEnd => text().nullable()();

  // Typed minutes so hours can always be recomputed exactly.
  IntColumn get attendanceMinutes => integer().withDefault(const Constant(0))();
  IntColumn get studyMinutes => integer().withDefault(const Constant(0))();
  IntColumn get questionMinutes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

@DataClassName('StepRow')
class Steps extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();

  /// `attend`, `study` or `questions`.
  TextColumn get kind => text()();
  IntColumn get minutes => integer()();
  TextColumn get suggestedStart => text().nullable()();
  TextColumn get suggestedEnd => text().nullable()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

@DataClassName('BreakRow')
class Breaks extends Table {
  TextColumn get id => text()();
  TextColumn get dayId => text().references(Days, #id)();
  IntColumn get afterPeriod => integer()();

  /// `break` or `free_time`.
  TextColumn get kind => text()();
  TextColumn get startClock => text()();
  TextColumn get endClock => text()();
  IntColumn get minutes => integer()();
  TextColumn get label => text().nullable()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

// ---------------------------------------------------------------------------
// User tables — progress, edits, sessions, notes, settings.
// ---------------------------------------------------------------------------

@DataClassName('UserTaskStateRow')
class UserTaskStates extends Table {
  TextColumn get taskId => text()();

  /// `not_started`, `in_progress`, `completed` or `postponed`.
  TextColumn get status => text().withDefault(const Constant('not_started'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{taskId};
}

@DataClassName('UserStepStateRow')
class UserStepStates extends Table {
  TextColumn get stepId => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  /// Mirrors `StepProgress.code`; the enum itself cannot be read in a const
  /// default expression, so the notStarted value (0) is spelled out here.
  IntColumn get progress => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{stepId};
}

@DataClassName('UserOverrideRow')
class UserOverrides extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `task`, `step`, `day` or `plan`.
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();

  /// Overridden field name, e.g. `dayId`, `minutes`, `type`.
  TextColumn get field => text()();

  /// JSON-encoded value so any field shape can be stored without a migration.
  TextColumn get value => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('UserAdditionRow')
class UserAdditions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dayId => text().references(Days, #id)();
  TextColumn get title => text()();
  IntColumn get minutes => integer()();
  TextColumn get kind => text().withDefault(const Constant('personal'))();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('FocusSessionRow')
class FocusSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get taskId => text().nullable()();
  TextColumn get taskTitle => text().nullable()();
  TextColumn get mode => text().withDefault(const Constant('pomodoro'))();
  TextColumn get stepId => text().nullable()();

  /// `focus` or `break`.
  TextColumn get phase => text()();
  IntColumn get plannedSeconds => integer()();
  IntColumn get actualSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

@DataClassName('NoteRow')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get taskId => text()();
  TextColumn get body => text()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('ReviewFlagRow')
class ReviewFlags extends Table {
  TextColumn get taskId => text()();
  DateTimeColumn get flaggedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{taskId};
}

@DataClassName('SettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => <Column>{key};
}
