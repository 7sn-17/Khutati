import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../application/focus_log_controller.dart';
import '../domain/focus_log.dart';

/// A full-screen record of every focus session.
///
/// The focus screen is a timer; this is the diary behind it: how much was
/// studied, when, in which mode, and how often a session ran to its end.
class FocusLogScreen extends ConsumerStatefulWidget {
  const FocusLogScreen({super.key});

  @override
  ConsumerState<FocusLogScreen> createState() => _FocusLogScreenState();
}

class _FocusLogScreenState extends ConsumerState<FocusLogScreen> {
  FocusLogRange _range = FocusLogRange.week;
  String _mode = 'all';

  KhutatiPalette get palette => context.palette;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FocusLogData> log = ref.watch(focusLogProvider);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(),
        titleSpacing: 0,
        title: Text(
          context.l10n.focusLogTitle,
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
      ),
      body: log.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.focusLogLoadError,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.muteSize,
                color: palette.mute,
              ),
            ),
          ),
        ),
        data: (FocusLogData data) => _body(data),
      ),
    );
  }

  Widget _body(FocusLogData data) {
    final DateTime now = DateTime.now();
    final FocusLogStats stats = data.stats(_range, now: now);
    final List<FocusLogDay> activity = data.activity(now: now);
    final List<FocusLogEntry> visible = data.filtered(
      _range,
      now: now,
      mode: _mode == 'all' ? null : _mode,
    );
    final List<FocusLogDay> days = FocusLog.group(
      _mode == 'all'
          ? visible
          : visible.where((FocusLogEntry entry) => entry.isFocus).toList(),
    );

    final List<Widget> header = <Widget>[
      _RangeBar(
        value: _range,
        onChanged: (FocusLogRange range) => setState(() => _range = range),
        palette: palette,
      ),
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _SummaryCard(
          key: ValueKey<String>('${_range.name}|$_mode'),
          stats: stats,
          palette: palette,
        ),
      ),
      const SizedBox(height: 18),
      _SectionTitle(title: 'نشاطك في آخر ١٤ يوماً', palette: palette),
      const SizedBox(height: 8),
      _ActivityChart(days: activity, palette: palette),
      const SizedBox(height: 18),
      _SectionTitle(title: 'الوقت حسب النمط', palette: palette),
      const SizedBox(height: 8),
      _ModeBreakdown(stats: stats, palette: palette),
      const SizedBox(height: 18),
      Row(
        children: <Widget>[
          Expanded(
            child: _SectionTitle(title: 'الجلسات', palette: palette),
          ),
          if (stats.sessionCount > 0)
            Text(
              '${stats.sessionCount} جلسة',
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 12,
                color: palette.mute,
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _ModeFilter(
        value: _mode,
        onChanged: (String mode) => setState(() => _mode = mode),
        palette: palette,
      ),
      const SizedBox(height: 10),
    ];

    final List<Object> rows = <Object>[];
    for (final FocusLogDay day in days) {
      rows.add(day);
      rows.addAll(day.entries);
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            KMetrics.appPaddingX,
            4,
            KMetrics.appPaddingX,
            0,
          ),
          sliver: SliverList.list(children: header),
        ),
        if (rows.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              KMetrics.appPaddingX,
              24,
              KMetrics.appPaddingX,
              KMetrics.appPaddingBottom,
            ),
            sliver: SliverToBoxAdapter(
              child: _EmptyLog(palette: palette, filtered: _mode != 'all'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              KMetrics.appPaddingX,
              0,
              KMetrics.appPaddingX,
              KMetrics.appPaddingBottom,
            ),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (BuildContext context, int index) {
                final Object row = rows[index];
                if (row is FocusLogDay) {
                  return _DayHeader(day: row, palette: palette);
                }
                final FocusLogEntry entry = row as FocusLogEntry;
                return _SessionTile(
                  entry: entry,
                  palette: palette,
                  onTap: () => _openDetails(entry),
                );
              },
            ),
          ),
      ],
    );
  }

  void _openDetails(FocusLogEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) =>
          _SessionDetails(entry: entry, palette: palette),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.value,
    required this.onChanged,
    required this.palette,
  });

  final FocusLogRange value;
  final ValueChanged<FocusLogRange> onChanged;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final Map<FocusLogRange, String> labels = <FocusLogRange, String>{
      FocusLogRange.today: l10n.focusLogRangeToday,
      FocusLogRange.week: l10n.focusLogRangeWeek,
      FocusLogRange.month: l10n.focusLogRangeMonth,
      FocusLogRange.all: l10n.focusLogRangeAll,
    };

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          for (final FocusLogRange range in FocusLogRange.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == range,
                label: labels[range],
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: value == range ? palette.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // The surface owns the hit test: an opaque InkWell makes the
                  // whole pill tappable, including its padding, and paints the
                  // ripple above the animated fill.
                  child: KInkSurface(
                    onTap: () => onChanged(range),
                    borderRadius: BorderRadius.circular(10),
                    expand: true,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      labels[range]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 13,
                        fontWeight: value == range
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: value == range ? Colors.black : palette.tx,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeFilter extends StatelessWidget {
  const _ModeFilter({
    required this.value,
    required this.onChanged,
    required this.palette,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<(String, String)> items = <(String, String)>[
      ('all', l10n.focusLogModeAll),
      ('pomodoro', l10n.focusLogModePomodoro),
      ('linked', l10n.focusLogModeLinked),
      ('free', l10n.focusLogModeFree),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final (String key, String label) in items)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Semantics(
                button: true,
                selected: value == key,
                label: label,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: value == key
                        ? palette.gold.withValues(alpha: 0.16)
                        : palette.card,
                    border: Border.all(
                      color: value == key ? palette.gold : palette.line,
                    ),
                    borderRadius: BorderRadius.circular(KMetrics.pillRadius),
                  ),
                  child: KInkSurface(
                    onTap: () => onChanged(key),
                    borderRadius: BorderRadius.circular(KMetrics.pillRadius),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 12,
                        color: value == key ? palette.gold : palette.tx,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats, required this.palette, super.key});

  final FocusLogStats stats;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'وقت التركيز',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 13,
                        color: palette.mute,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _longDuration(stats.focusSeconds),
                      style: TextStyle(
                        fontFamily: KTypography.displayFamily,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: palette.tx,
                      ),
                    ),
                  ],
                ),
              ),
              _StreakBadge(days: stats.streakDays, palette: palette),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: palette.line),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _SummaryStat(
                label: 'جلسات',
                value: '${stats.sessionCount}',
                palette: palette,
                valueKey: const Key('focus-log-sessions'),
              ),
              _SummaryStat(
                label: 'مكتملة',
                value: stats.sessionCount == 0
                    ? '—'
                    : '${(stats.completionRate * 100).round()}%',
                palette: palette,
              ),
              _SummaryStat(
                label: 'متوسط الجلسة',
                value: stats.sessionCount == 0
                    ? '—'
                    : _shortDuration(stats.averageSeconds),
                palette: palette,
              ),
              _SummaryStat(
                label: 'أفضل يوم',
                value: stats.bestDaySeconds == 0
                    ? '—'
                    : _shortDuration(stats.bestDaySeconds),
                palette: palette,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days, required this.palette});

  final int days;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final bool active = days > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.gold.withValues(alpha: active ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: palette.gold.withValues(alpha: active ? 0.55 : 0.25),
        ),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.local_fire_department_rounded,
            size: 20,
            color: active ? palette.gold : palette.mute,
          ),
          const SizedBox(height: 2),
          Text(
            active ? '$days' : '0',
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: active ? palette.gold : palette.mute,
            ),
          ),
          Text(
            'يوم متتابع',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 10,
              color: palette.mute,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.palette,
    this.valueKey,
  });

  final String label;
  final String value;
  final KhutatiPalette palette;

  /// Lets a test read one specific figure without relying on the text, which
  /// can legitimately repeat across stats and the streak badge.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            key: valueKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.tx,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 10.5,
              color: palette.mute,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity chart
// ---------------------------------------------------------------------------

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.days, required this.palette});

  final List<FocusLogDay> days;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateTime.now();
    final int peak = days.fold<int>(
      0,
      (int best, FocusLogDay day) => math.max(best, day.focusSeconds),
    );
    return KCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final FocusLogDay day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Tooltip(
                      message: _longDuration(day.focusSeconds),
                      child: Container(
                        height:
                            6.0 +
                            58.0 * (peak == 0 ? 0.0 : day.focusSeconds / peak),
                        decoration: BoxDecoration(
                          color: _isToday(day.day, today)
                              ? palette.gold
                              : (day.focusSeconds == 0
                                    ? palette.line
                                    : palette.ok.withValues(alpha: 0.75)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${day.day.day}',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 9,
                        color: _isToday(day.day, today)
                            ? palette.gold
                            : palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ---------------------------------------------------------------------------
// Mode breakdown
// ---------------------------------------------------------------------------

class _ModeBreakdown extends StatelessWidget {
  const _ModeBreakdown({required this.stats, required this.palette});

  final FocusLogStats stats;
  final KhutatiPalette palette;

  static const List<(String, String)> _modes = <(String, String)>[
    ('pomodoro', 'بومودورو'),
    ('linked', 'مرتبط بمهمة'),
    ('free', 'مؤقت حر'),
  ];

  @override
  Widget build(BuildContext context) {
    final int total = stats.focusSeconds;
    return KCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          for (final (String key, String label) in _modes)
            Padding(
              padding: EdgeInsets.only(bottom: key == _modes.last.$1 ? 0 : 12),
              child: _ModeRow(
                label: label,
                seconds: stats.secondsByMode[key] ?? 0,
                total: total,
                color: _modeColor(key, palette),
                palette: palette,
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.label,
    required this.seconds,
    required this.total,
    required this.color,
    required this.palette,
  });

  final String label;
  final int seconds;
  final int total;
  final Color color;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final double share = total == 0 ? 0.0 : seconds / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 13,
                  color: palette.tx,
                ),
              ),
            ),
            Text(
              seconds == 0 ? '—' : _shortDuration(seconds),
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: seconds == 0 ? palette.mute : palette.tx,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: <Widget>[
              Container(height: 6, color: palette.line),
              FractionallySizedBox(
                widthFactor: share.clamp(0.0, 1.0),
                child: Container(height: 6, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Session list
// ---------------------------------------------------------------------------

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.palette});

  final FocusLogDay day;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: <Widget>[
          Text(
            _dateLabel(day.day),
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.gold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: palette.line)),
          const SizedBox(width: 8),
          Text(
            _shortDuration(day.focusSeconds),
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 11,
              color: palette.mute,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.entry,
    required this.palette,
    required this.onTap,
  });

  final FocusLogEntry entry;
  final KhutatiPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isBreak = !entry.isFocus;
    final Color accent = isBreak
        ? palette.mute
        : _modeColor(entry.mode, palette);
    final String title = (entry.taskTitle?.isNotEmpty ?? false)
        ? entry.taskTitle!
        : (isBreak ? 'استراحة' : _modeLabel(entry.mode));
    final String status = isBreak
        ? 'استراحة'
        : (entry.completed ? 'مكتملة' : 'متوقفة');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KCard(
        showPattern: false,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isBreak
                    ? Icons.coffee_rounded
                    : (entry.completed
                          ? Icons.check_rounded
                          : Icons.timelapse_rounded),
                size: 19,
                color: accent,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: palette.tx,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_timeOf(entry.startedAt)} · ${_shortDuration(entry.actualSeconds)} · $status',
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 11.5,
                      color: palette.mute,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              size: 20,
              color: palette.mute.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDetails extends StatelessWidget {
  const _SessionDetails({required this.entry, required this.palette});

  final FocusLogEntry entry;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final bool isBreak = !entry.isFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            (entry.taskTitle?.isNotEmpty ?? false)
                ? entry.taskTitle!
                : (isBreak ? 'استراحة' : _modeLabel(entry.mode)),
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.tx,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_dateLabel(entry.day)} · ${_timeOf(entry.startedAt)}'
            '${entry.endedAt == null ? '' : ' – ${_timeOf(entry.endedAt!)}'}',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 12,
              color: palette.mute,
            ),
          ),
          const SizedBox(height: 18),
          _DetailRow(
            label: 'النمط',
            value: isBreak ? 'استراحة' : _modeLabel(entry.mode),
            palette: palette,
          ),
          _DetailRow(
            label: 'المدة الفعلية',
            value: _longDuration(entry.actualSeconds),
            palette: palette,
          ),
          _DetailRow(
            label: 'المدة المخططة',
            value: _longDuration(entry.plannedSeconds),
            palette: palette,
          ),
          _DetailRow(
            label: 'الحالة',
            value: isBreak
                ? 'استراحة'
                : (entry.completed ? 'اكتملت في وقتها' : 'أُنهيت مبكراً'),
            palette: palette,
          ),
          if (entry.taskId != null)
            _DetailRow(label: 'مرتبطة بمهمة', value: 'نعم', palette: palette),
          const SizedBox(height: 10),
          Text(
            'تُسجَّل الجلسات التي تتجاوز دقيقة واحدة فقط.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 11,
              color: palette.mute,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 13,
                color: palette.mute,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.tx,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLog extends StatelessWidget {
  const _EmptyLog({required this.palette, required this.filtered});

  final KhutatiPalette palette;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(
          Icons.history_toggle_off_rounded,
          size: 56,
          color: palette.mute.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 12),
        Text(
          filtered
              ? 'لا توجد جلسات بهذا النمط في هذه الفترة'
              : 'لم تبدأ أي جلسة تركيز بعد',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'كل جلسة تتجاوز دقيقة تُحفظ هنا تلقائياً.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            color: palette.mute.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/focus');
            }
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('ابدأ جلسة تركيز'),
          style: TextButton.styleFrom(foregroundColor: palette.gold),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.palette});

  final String title;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: KTypography.displayFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: palette.tx,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

Color _modeColor(String mode, KhutatiPalette palette) {
  switch (mode) {
    case 'linked':
      return const Color(0xFF6AA6FF);
    case 'free':
      return palette.ok;
    default:
      return palette.gold;
  }
}

String _modeLabel(String mode) {
  switch (mode) {
    case 'linked':
      return 'مرتبط بمهمة';
    case 'free':
      return 'مؤقت حر';
    default:
      return 'بومودورو';
  }
}

String _shortDuration(int seconds) {
  final int minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes د';
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  return rest == 0 ? '$hours س' : '$hours س $rest د';
}

String _longDuration(int seconds) {
  final int minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes دقيقة';
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  return rest == 0 ? '$hours ساعة' : '$hours ساعة و$rest دقيقة';
}

String _timeOf(DateTime time) {
  final String h = time.hour.toString().padLeft(2, '0');
  final String m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

const List<String> _weekdays = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const List<String> _months = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String _dateLabel(DateTime date) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(date.year, date.month, date.day);
  final int diff = today.difference(day).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
}
