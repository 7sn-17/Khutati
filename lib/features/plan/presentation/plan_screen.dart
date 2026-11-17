import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/utils/format.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../l10n/l10n.dart';
import '../application/plan_browser_controller.dart';

/// Plan (PRD 5.3) — the whole 68-day journey, browsable by week and day.
///
/// The screen is read-only by design (plan editing is deferred): it is a calm,
/// high-density map of the plan with real dates, subject categories, weekly
/// totals and local search across lessons and chapters.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PlanBrowserData?> plan = ref.watch(planBrowserProvider);

    return plan.when(
      data: (PlanBrowserData? data) =>
          data == null ? const _PlanError() : _PlanBody(data: data),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => const _PlanError(),
    );
  }
}

class _PlanBody extends ConsumerStatefulWidget {
  const _PlanBody({required this.data});

  final PlanBrowserData data;

  @override
  ConsumerState<_PlanBody> createState() => _PlanBodyState();
}

class _PlanBodyState extends ConsumerState<_PlanBody> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _dayKeys = <int, GlobalKey>{};
  int? _week;
  int? _expandedDay;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final String next = _search.text.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  GlobalKey _keyFor(int dayNumber) {
    return _dayKeys.putIfAbsent(dayNumber, () => GlobalKey());
  }

  void _openDay(PlanDayData day) {
    final int dayNumber = day.day.dayNumber;
    _search.clear();
    setState(() {
      _week = widget.data.calendar.weekOfDay(dayNumber);
      _expandedDay = dayNumber;
      _query = '';
    });
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      final BuildContext? target = _keyFor(dayNumber).currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlanBrowserData data = widget.data;
    final AppLocalizations l10n = context.l10n;
    final KhutatiFormat format = KhutatiFormat(l10n);
    final int weekNumber = _week ?? data.currentWeek;
    final PlanWeekData week = data.week(weekNumber);
    final int expandedDay = _expandedDay ?? data.todayDay.day.dayNumber;
    final List<PlanSearchHit> hits = data.search(_query);
    final int completedDays = data.days
        .where((PlanDayData day) => !day.isRest && day.progress.isComplete)
        .length;
    final int studyDays = data.days
        .where((PlanDayData day) => !day.isRest)
        .length;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(planBrowserProvider);
        await ref.read(planBrowserProvider.future);
      },
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          KMetrics.appPaddingX,
          KMetrics.appPaddingTop,
          KMetrics.appPaddingX,
          KMetrics.appPaddingBottom,
        ),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.planTitle,
                      style: TextStyle(
                        fontFamily: KTypography.displayFamily,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: palette(context).tx,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.today.window == PlanWindow.beforeStart
                          ? l10n.planStartsOn(
                              KhutatiFormat.planDate(data.calendar.startDate),
                            )
                          : l10n.planSubtitle,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.muteSize,
                        color: palette(context).mute,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _OverallRing(data: data),
            ],
          ),
          const SizedBox(height: 14),
          _OverallCard(
            data: data,
            completedDays: completedDays,
            studyDays: studyDays,
            format: format,
            l10n: l10n,
          ),
          const SizedBox(height: 14),
          _SearchField(controller: _search, query: _query),
          if (_query.isNotEmpty)
            ..._searchResults(context, l10n, format, hits)
          else ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.calendar.weekCount,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final PlanWeekData chipWeek = data.week(index + 1);
                  return _WeekChip(
                    week: chipWeek,
                    selected: chipWeek.number == weekNumber,
                    l10n: l10n,
                    onTap: () {
                      ref.read(hapticsProvider).selection();
                      setState(() => _week = chipWeek.number);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _WeekSummary(week: week, format: format, l10n: l10n),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Text(
                  l10n.planDays,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: KTypography.h2Size,
                    fontWeight: FontWeight.w700,
                    color: palette(context).tx,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.planDayCount(week.days.length),
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.smallSize,
                    color: palette(context).mute,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final PlanDayData day in week.days)
              Padding(
                key: _keyFor(day.day.dayNumber),
                padding: const EdgeInsets.only(bottom: 10),
                child: _DayCard(
                  day: day,
                  format: format,
                  l10n: l10n,
                  expanded: day.day.dayNumber == expandedDay,
                  onTap: () {
                    ref.read(hapticsProvider).selection();
                    setState(
                      () => _expandedDay = day.day.dayNumber == expandedDay
                          ? -1
                          : day.day.dayNumber,
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _searchResults(
    BuildContext context,
    AppLocalizations l10n,
    KhutatiFormat format,
    List<PlanSearchHit> hits,
  ) {
    final KhutatiPalette palette = context.palette;
    return <Widget>[
      const SizedBox(height: 18),
      Row(
        children: <Widget>[
          Text(
            l10n.planSearchResults,
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: KTypography.h2Size,
              fontWeight: FontWeight.w700,
              color: palette.tx,
            ),
          ),
          const Spacer(),
          Text(
            '${hits.length}',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.smallSize,
              color: palette.mute,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (hits.isEmpty)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(KMetrics.cardRadius),
            border: Border.all(color: palette.line),
          ),
          child: Text(
            l10n.planSearchEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.muteSize,
              height: 1.6,
              color: palette.mute,
            ),
          ),
        )
      else
        for (final PlanSearchHit hit in hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SearchResult(
              hit: hit,
              format: format,
              l10n: l10n,
              onTap: () => _openDay(hit.day),
            ),
          ),
    ];
  }
}

KhutatiPalette palette(BuildContext context) => context.palette;

class _OverallRing extends StatelessWidget {
  const _OverallRing({required this.data});

  final PlanBrowserData data;

  @override
  Widget build(BuildContext context) {
    return KProgressRing(
      progress: data.overall.fraction,
      numeral: '${(data.overall.fraction * 100).round()}%',
      size: 78,
      color: context.palette.gold,
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.data,
    required this.completedDays,
    required this.studyDays,
    required this.format,
    required this.l10n,
  });

  final PlanBrowserData data;
  final int completedDays;
  final int studyDays;
  final KhutatiFormat format;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return KCard(
      showPattern: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.planOverall,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.smallSize,
                    fontWeight: FontWeight.w600,
                    color: palette.tx,
                  ),
                ),
              ),
              Text(
                l10n.planOverallValue(completedDays, studyDays),
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.tagSize,
                  color: palette.mute,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          KProgressBar(value: data.overall.fraction, color: palette.gold),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniMetric(
                  label: l10n.todayDone,
                  value: format.duration(data.overall.completedMinutes),
                  color: palette.ok,
                ),
              ),
              Container(width: 1, height: 28, color: palette.line),
              Expanded(
                child: _MiniMetric(
                  label: l10n.planRemaining,
                  value: format.duration(data.overall.remainingMinutes),
                  color: palette.mute,
                ),
              ),
              Container(width: 1, height: 28, color: palette.line),
              Expanded(
                child: _MiniMetric(
                  label: l10n.planHours,
                  value: format.duration(data.overall.plannedMinutes),
                  color: palette.gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: KTypography.smallSize,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: KTypography.tagSize,
            color: palette.mute,
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.query});

  final TextEditingController controller;
  final String query;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: TextStyle(
        fontFamily: KTypography.bodyFamily,
        fontSize: KTypography.muteSize,
        color: palette.tx,
      ),
      decoration: InputDecoration(
        hintText: context.l10n.planSearchHint,
        hintStyle: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: KTypography.muteSize,
          color: palette.mute,
        ),
        prefixIcon: Icon(Icons.search_rounded, size: 21, color: palette.mute),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: context.l10n.planSearchClear,
                onPressed: controller.clear,
                icon: Icon(Icons.close_rounded, size: 19, color: palette.mute),
              ),
        filled: true,
        fillColor: palette.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
          borderSide: BorderSide(color: palette.gold, width: 1.2),
        ),
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({
    required this.week,
    required this.selected,
    required this.l10n,
    required this.onTap,
  });

  final PlanWeekData week;
  final bool selected;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color fg = selected ? palette.bg : palette.tx;
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.planWeek(week.number),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 148,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? palette.tx : palette.card,
            borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
            border: Border.all(color: selected ? palette.tx : palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                l10n.planWeek(week.number),
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.smallSize,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _weekRange(week),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 11,
                  color: selected
                      ? palette.bg.withValues(alpha: 0.72)
                      : palette.mute,
                ),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 3,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ColoredBox(
                          color: selected
                              ? palette.bg.withValues(alpha: 0.2)
                              : palette.line,
                        ),
                      ),
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: week.progress.fraction,
                          child: ColoredBox(
                            color: selected ? palette.gold : palette.redtx,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _weekRange(PlanWeekData week) {
  final String first = KhutatiFormat.planDate(week.firstDate);
  final String last = KhutatiFormat.planDate(week.lastDate);
  return '$first – $last';
}

class _WeekSummary extends StatelessWidget {
  const _WeekSummary({
    required this.week,
    required this.format,
    required this.l10n,
  });

  final PlanWeekData week;
  final KhutatiFormat format;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final int tasks = week.days.fold<int>(
      0,
      (int sum, PlanDayData day) => sum + day.tasks.length,
    );
    final int doneTasks = week.days.fold<int>(
      0,
      (int sum, PlanDayData day) =>
          sum + day.tasks.where((PlanTask task) => task.isComplete).length,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(KMetrics.cardRadius),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                l10n.planWeekSummary,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.smallSize,
                  fontWeight: FontWeight.w600,
                  color: palette.tx,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _weekRange(week),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 11,
                    color: palette.mute,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _WeekMetric(
                  label: l10n.planTasks,
                  value: '$doneTasks / $tasks',
                  icon: Icons.checklist_rounded,
                  color: palette.ok,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WeekMetric(
                  label: l10n.todayDone,
                  value: format.duration(week.progress.completedMinutes),
                  icon: Icons.schedule_rounded,
                  color: palette.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WeekMetric(
                  label: l10n.planRemaining,
                  value: format.duration(week.progress.remainingMinutes),
                  icon: Icons.hourglass_bottom_rounded,
                  color: palette.redtx,
                ),
              ),
            ],
          ),
          if (week.subjects.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              l10n.planSubjects,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: palette.mute,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final PlanSubjectGroup subject in week.subjects)
                  _SubjectChip(subject: subject),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekMetric extends StatelessWidget {
  const _WeekMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 10,
                    color: palette.mute,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.smallSize,
              fontWeight: FontWeight.w600,
              color: palette.tx,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({required this.subject});

  final PlanSubjectGroup subject;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: subject.accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(KMetrics.pillRadius),
        border: Border.all(color: subject.accent.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: subject.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            subject.name,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: palette.tx,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.format,
    required this.l10n,
    required this.expanded,
    required this.onTap,
  });

  final PlanDayData day;
  final KhutatiFormat format;
  final AppLocalizations l10n;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final (String status, Color statusColor) = _status(context);
    final DateTime date = day.date;
    final String weekday = KhutatiFormat.westernDigits(
      DateFormat('EEEE', 'ar').format(date),
    );
    final String month = KhutatiFormat.westernDigits(
      DateFormat('MMM', 'ar').format(date),
    );
    final String title = (day.day.headerTitle ?? '').trim().isNotEmpty
        ? day.day.headerTitle!.trim()
        : day.isRest
        ? l10n.planRestTitle
        : day.isPractical
        ? l10n.planPracticalDay
        : l10n.planStudyDay;
    final int taskCount = day.tasks.length;
    final Color border = day.isToday
        ? palette.gold.withValues(alpha: 0.72)
        : palette.line;

    final Widget card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KMetrics.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: day.isRest
                ? palette.card.withValues(alpha: 0.55)
                : palette.card,
            borderRadius: BorderRadius.circular(KMetrics.cardRadius),
            border: day.isToday
                ? Border.all(color: border, width: 1.4)
                : Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 51,
                    child: Column(
                      children: <Widget>[
                        Text(
                          weekday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: 10,
                            color: day.isToday ? palette.gold : palette.mute,
                          ),
                        ),
                        Text(
                          '${day.day.dayNumber}',
                          style: TextStyle(
                            fontFamily: KTypography.displayFamily,
                            fontSize: 27,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: day.isToday ? palette.gold : palette.tx,
                          ),
                        ),
                        Text(
                          month,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: 10,
                            color: palette.mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(
                                  KMetrics.pillRadius,
                                ),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.42),
                                ),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l10n.planTaskCount(taskCount),
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: 10,
                                  color: palette.mute,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: KTypography.muteSize,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: palette.tx,
                          ),
                        ),
                        if (day.isRest) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            l10n.planRestBody,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: KTypography.bodyFamily,
                              fontSize: 11,
                              height: 1.4,
                              color: palette.mute,
                            ),
                          ),
                        ] else ...<Widget>[
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.schedule_rounded,
                                size: 12,
                                color: palette.mute,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                format.duration(day.progress.plannedMinutes),
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: 10,
                                  color: palette.mute,
                                ),
                              ),
                              if (taskCount > 0) ...<Widget>[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: SizedBox(
                                      height: 3,
                                      child: Stack(
                                        children: <Widget>[
                                          Positioned.fill(
                                            child: ColoredBox(
                                              color: palette.line,
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: FractionallySizedBox(
                                              alignment: AlignmentDirectional
                                                  .centerStart,
                                              widthFactor:
                                                  day.progress.fraction,
                                              child: ColoredBox(
                                                color: day.progress.isComplete
                                                    ? palette.ok
                                                    : palette.redtx,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (day.groups.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: <Widget>[
                                for (final PlanSubjectGroup group
                                    in day.groups.take(3))
                                  _TinySubject(group: group),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: palette.mute,
                      ),
                    ),
                  ),
                ],
              ),
              if (expanded) ...<Widget>[
                const SizedBox(height: 12),
                Container(height: 1, color: palette.line),
                if (day.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      l10n.planRestBody,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                        height: 1.6,
                        color: palette.mute,
                      ),
                    ),
                  )
                else
                  for (final PlanSubjectGroup group in day.groups)
                    _GroupBlock(group: group, format: format),
                if (day.status == PlanDayStatus.overdue) ...<Widget>[
                  const SizedBox(height: 12),
                  KButton(
                    label: l10n.pastTasksReview,
                    variant: KButtonVariant.secondary,
                    expand: true,
                    onPressed: () =>
                        context.push('/past-tasks?day=${day.day.dayNumber}'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );

    if (!day.isRest) return card;
    return CustomPaint(
      painter: _DashedBorderPainter(color: day.isToday ? border : palette.line),
      child: card,
    );
  }

  (String, Color) _status(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return switch (day.status) {
      PlanDayStatus.completed => (l10n.planStatusCompleted, palette.ok),
      PlanDayStatus.current => (l10n.planStatusCurrent, palette.gold),
      PlanDayStatus.overdue => (l10n.planStatusOverdue, palette.redtx),
      PlanDayStatus.upcoming => (l10n.planStatusUpcoming, palette.mute),
      PlanDayStatus.rest => (l10n.planStatusRest, palette.gold),
    };
  }
}

class _TinySubject extends StatelessWidget {
  const _TinySubject({required this.group});

  final PlanSubjectGroup group;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: group.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          group.name,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 10,
            color: palette.mute,
          ),
        ),
      ],
    );
  }
}

/// The ring mirrors the same fraction Today shows, so a partial step is
/// visibly half-done in both tabs. It only appears once work has started, and
/// it carries its own trailing gap so the row keeps its spacing either way.
Widget _taskProgressRing(BuildContext context, PlanTask task) {
  if (task.isComplete || task.fraction <= 0) return const SizedBox.shrink();
  final KhutatiPalette palette = context.palette;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          value: task.fraction,
          strokeWidth: 2,
          color: palette.gold,
          backgroundColor: palette.line,
        ),
      ),
      const SizedBox(width: 8),
    ],
  );
}

IconData _taskStatusIcon(PlanTask task) => task.isComplete
    ? Icons.check_circle_rounded
    : task.status == PlanTaskStatus.inProgress
    ? Icons.timelapse_rounded
    : task.status == PlanTaskStatus.postponed
    ? Icons.schedule_send_rounded
    : Icons.radio_button_unchecked_rounded;

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({required this.group, required this.format});

  final PlanSubjectGroup group;
  final KhutatiFormat format;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: group.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.name,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.smallSize,
                    fontWeight: FontWeight.w600,
                    color: palette.tx,
                  ),
                ),
              ),
              Text(
                format.duration(group.minutes),
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 10,
                  color: palette.mute,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (final PlanTask task in group.tasks) _TaskLine(task: task),
        ],
      ),
    );
  }
}

class _TaskLine extends ConsumerWidget {
  const _TaskLine({required this.task});

  final PlanTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final IconData icon = task.type == PlanTaskType.courseQuestions
        ? Icons.quiz_outlined
        : Icons.play_circle_outline_rounded;
    final String kind = task.type == PlanTaskType.foundation
        ? l10n.planTaskVideo
        : task.type == PlanTaskType.lecture
        ? l10n.planTaskLecture
        : l10n.planTaskQuestions;
    final String? subtitle = task.groupTitle?.trim();
    final String title = task.title;

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            size: 15,
            color: task.isComplete ? palette.ok : palette.mute,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: task.isComplete ? palette.mute : palette.tx,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 10,
                      color: palette.mute,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$kind · ${task.plannedMinutes} ${l10n.unitMinute}',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 10,
              color: palette.mute,
            ),
          ),
          const SizedBox(width: 8),
          _taskProgressRing(context, task),
          PopupMenuButton<PlanTaskStatus>(
            tooltip: l10n.planTaskStatusTooltip,
            onSelected: (PlanTaskStatus status) async {
              ref.read(hapticsProvider).selection();
              await ref.read(planActionsProvider).setTaskStatus(task.id, status);
              if (!context.mounted) return;
              if (status == PlanTaskStatus.completed) {
                showKToast(context, l10n.galleryToast);
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<PlanTaskStatus>>[
                  for (final PlanTaskStatus status in PlanTaskStatus.values)
                    PopupMenuItem<PlanTaskStatus>(
                      value: status,
                      child: Text(_planTaskStatusLabel(l10n, status)),
                    ),
                ],
            child: Icon(
              _taskStatusIcon(task),
              size: 18,
              color: task.isComplete ? palette.ok : palette.mute,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResult extends StatelessWidget {
  const _SearchResult({
    required this.hit,
    required this.format,
    required this.l10n,
    required this.onTap,
  });

  final PlanSearchHit hit;
  final KhutatiFormat format;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final PlanTask task = hit.task;
    final Color accent =
        hit.day.subjectAccents[task.subjectKey] ?? palette.gold;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${task.subjectName ?? task.subjectKey} — ${task.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.tx,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${l10n.planSearchDay(hit.day.day.dayNumber, KhutatiFormat.planDate(hit.day.date))} · ${format.duration(task.plannedMinutes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 10,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: palette.mute,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(KMetrics.cardRadius),
        ),
      );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PlanError extends ConsumerWidget {
  const _PlanError();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KhutatiPalette palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.map_outlined, size: 30, color: palette.mute),
            const SizedBox(height: 10),
            Text(
              context.l10n.planLoadError,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.muteSize,
                color: palette.mute,
              ),
            ),
            const SizedBox(height: 12),
            KButton(
              label: context.l10n.planRetry,
              variant: KButtonVariant.secondary,
              onPressed: () => ref.invalidate(planBrowserProvider),
            ),
          ],
        ),
      ),
    );
  }
}


String _planTaskStatusLabel(AppLocalizations l10n, PlanTaskStatus status) {
  switch (status) {
    case PlanTaskStatus.notStarted:
      return l10n.planTaskStatusNotStarted;
    case PlanTaskStatus.inProgress:
      return l10n.planTaskStatusInProgress;
    case PlanTaskStatus.completed:
      return l10n.planTaskStatusCompleted;
    case PlanTaskStatus.postponed:
      return l10n.planTaskStatusPostponed;
  }
}
