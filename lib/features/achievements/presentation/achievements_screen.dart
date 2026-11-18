import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../application/achievements_controller.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AchievementsData?> data = ref.watch(achievementsProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) => Center(child: Text('$e')),
      data: (AchievementsData? d) {
        if (d == null) {
          return Center(
            child: Text(context.l10n.achievementsPlaceholder),
          );
        }
        return _AchievementsBody(data: d);
      },
    );
  }
}

class _AchievementsBody extends StatefulWidget {
  const _AchievementsBody({required this.data});
  final AchievementsData data;

  @override
  State<_AchievementsBody> createState() => _AchievementsBodyState();
}

class _AchievementsBodyState extends State<_AchievementsBody> {
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.data.todayDayNumber > 0
        ? widget.data.todayDayNumber
        : 1;
  }

  @override
  Widget build(BuildContext context) {
    final AchievementsData d = widget.data;
    final KhutatiPalette palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _HeroSection(data: d),
          const SizedBox(height: 24),
          _BadgesSection(data: d),
          const SizedBox(height: 24),
          _DayMapSection(
            data: d,
            selectedDay: _selectedDay,
            onSelect: (int day) => setState(() => _selectedDay = day),
          ),
          const SizedBox(height: 24),
          _StudyHoursSection(data: d),
          const SizedBox(height: 24),
          _SubjectsSection(data: d),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.data});
  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: _HexagonPattern()),
          Container(
            decoration: const BoxDecoration(color: Color(0xFF0D1A2D)),
            padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'إجمالي نقاطك',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      '${data.totalPoints}',
                      style: const TextStyle(
                        fontFamily: 'Reem Kufi',
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8B65A),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8B65A).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '+${data.pointsToday} نقطة اليوم',
                        style: const TextStyle(
                          color: Color(0xFFE8B65A),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'سلسلتك',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      '${data.streak}',
                      style: const TextStyle(
                        fontFamily: 'Reem Kufi',
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'أيام متتالية من الإنجاز',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'آخر 7 أيام',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List<Widget>.generate(7, (int i) {
              final String status = data.last7[i];
              final Color dotColor = status == 'done'
                  ? const Color(0xFF7CCBB0)
                  : status == 'rest'
                  ? Colors.transparent
                  : status == 'today'
                  ? const Color(0xFF1C3150)
                  : Colors.transparent;
              final Border border = status == 'rest'
                  ? Border.all(
                      color: Colors.white38,
                      style: BorderStyle.solid,
                      width: 2,
                    )
                  : status == 'today'
                  ? Border.all(color: Colors.white, width: 2.5)
                  : status == 'wait'
                  ? Border.all(color: const Color(0xFFE8B65A), width: 2)
                  : Border.all(color: Colors.white24, width: 2);
              return Column(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: dotColor,
                      border: border,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: status == 'done'
                        ? const Icon(Icons.check, size: 16, color: Color(0xFF0D1A2D))
                        : status == 'rest'
                        ? const Text('–', style: TextStyle(color: Colors.white70))
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status == 'today' ? 'اليوم' : '',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: const <Widget>[
              _LegendDot(color: Color(0xFF7CCBB0), label: 'أنجزت يومك'),
              SizedBox(width: 14),
              _LegendDot(color: Colors.transparent, dashed: true, label: 'يوم راحة'),
              SizedBox(width: 14),
              _LegendDot(color: Color(0xFFE8B65A), hollow: true, label: 'مهام تنتظرك'),
            ],
          ),
          if (data.nextBadge != null) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF26395A))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'وسامك القادم: ${_tierName(data.nextBadge!.level)} في ${data.nextBadge!.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      Text(
                        '${data.nextBadge!.current} من ${data.nextBadge!.nextThreshold}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: data.nextBadge!.fraction,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF26395A),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFE8B65A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يتبقّى ${data.nextBadge!.nextThreshold! - data.nextBadge!.current} ${data.nextBadge!.unit} فقط.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.dashed = false,
    this.hollow = false,
  });
  final Color color;
  final String label;
  final bool dashed;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: hollow ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(5),
            border: dashed
                ? Border.all(color: Colors.white38, style: BorderStyle.solid)
                : hollow
                ? Border.all(color: const Color(0xFFE8B65A))
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

String _tierName(int level) {
  const List<String> names = <String>['برونزي', 'فضي', 'ذهبي', 'زمردي', 'ماسي'];
  if (level <= 0) return names[0];
  if (level > names.length) return names.last;
  return names[level - 1];
}

// ---------------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------------

class _BadgesSection extends StatelessWidget {
  const _BadgesSection({required this.data});
  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final int earned = data.badges.fold<int>(0, (int a, BadgeInfo b) => a + b.level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'الأوسمة',
              style: TextStyle(
                fontFamily: KTypography.displayFamily,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: palette.tx,
              ),
            ),
            Text(
              'جمعت $earned وسام من ${data.badges.length * 5}.',
              style: TextStyle(color: palette.mute, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...data.badges.map((BadgeInfo b) => _BadgeCard(badge: b)),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});
  final BadgeInfo badge;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final int tierIndex = badge.level > 0 ? badge.level - 1 : -1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            height: 99,
            child: CustomPaint(
              painter: _BadgePainter(tier: tierIndex, icon: badge.icon),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  badge.name,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                  ),
                ),
                Text(
                  badge.level > 0
                      ? 'المستوى ${_tierName(badge.level)} (${badge.level} من 5)'
                      : 'لم تبدأ بعد',
                  style: TextStyle(color: palette.mute, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (badge.nextThreshold != null) ...<Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: badge.fraction,
                      minHeight: 8,
                      backgroundColor: palette.line,
                      valueColor: AlwaysStoppedAnimation<Color>(palette.gold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        '${badge.current} من ${badge.nextThreshold} ${badge.unit}',
                        style: TextStyle(color: palette.mute, fontSize: 12),
                      ),
                      Text(
                        'التالي: ${_tierName(badge.level + 1)}',
                        style: TextStyle(color: palette.mute, fontSize: 12),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    'أنهيت كل المستويات. أحسنت!',
                    style: TextStyle(color: palette.ok, fontSize: 13),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: badge.thresholds
                      .asMap()
                      .entries
                      .map((MapEntry<int, int> e) {
                        final bool earned = e.key < badge.level;
                        return Column(
                          children: <Widget>[
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: earned ? palette.gold : palette.line,
                                  width: 2,
                                  style: earned
                                      ? BorderStyle.solid
                                      : BorderStyle.solid,
                                ),
                                color: earned
                                    ? palette.gold.withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${e.key + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: earned ? palette.gold : palette.mute,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.value}',
                              style: TextStyle(
                                fontSize: 11,
                                color: palette.mute,
                              ),
                            ),
                          ],
                        );
                      })
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day map
// ---------------------------------------------------------------------------

class _DayMapSection extends StatelessWidget {
  const _DayMapSection({
    required this.data,
    required this.selectedDay,
    required this.onSelect,
  });
  final AchievementsData data;
  final int? selectedDay;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'خريطة الأيام',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
        Text(
          'كل مربع يوم من أيام الخطة. اضغط على أي يوم لترى تفاصيله.',
          style: TextStyle(color: palette.mute, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.card,
            border: Border.all(color: palette.line),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '${data.completedDays} يوماً مكتملاً من ${data.totalDays}',
                    style: TextStyle(color: palette.tx, fontSize: 14),
                  ),
                  Text(
                    '${data.totalDays > 0 ? (data.completedDays / data.totalDays * 100).round() : 0}%',
                    style: TextStyle(color: palette.mute, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: data.totalDays > 0
                      ? data.completedDays / data.totalDays
                      : 0,
                  minHeight: 8,
                  backgroundColor: palette.line,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.ok),
                ),
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  childAspectRatio: 1,
                ),
                itemCount: data.totalDays,
                itemBuilder: (BuildContext context, int index) {
                  final int day = index + 1;
                  final String status = data.dayStatus[day] ?? 'future';
                  final bool selected = selectedDay == day;
                  Color bg = palette.card2;
                  Color border = palette.line;
                  Color fg = palette.mute;
                  if (status == 'done') {
                    bg = palette.ok;
                    border = palette.ok;
                    fg = palette.bg;
                  } else if (status == 'rest') {
                    bg = Colors.transparent;
                    border = palette.mute;
                  } else if (status == 'today') {
                    bg = palette.card;
                    border = palette.tx;
                    fg = palette.tx;
                  } else if (status == 'wait') {
                    bg = Colors.transparent;
                    border = palette.gold;
                    fg = palette.tx;
                  }
                  return GestureDetector(
                    onTap: () => onSelect(day),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border.all(color: border, width: selected ? 2.5 : 1.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: status == 'today' ? FontWeight.w700 : FontWeight.normal,
                          color: fg,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _DayDetailCard(data: data, day: selectedDay),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayDetailCard extends StatelessWidget {
  const _DayDetailCard({required this.data, required this.day});
  final AchievementsData data;
  final int? day;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final int d = day ?? data.todayDayNumber;
    if (d < 1 || d > data.totalDays) {
      return const SizedBox.shrink();
    }
    final String status = data.dayStatus[d] ?? 'future';
    final String statusLabel = status == 'done'
        ? 'مكتمل'
        : status == 'rest'
        ? 'يوم راحة مجدول. لا يقطع سلسلتك.'
        : status == 'today'
        ? 'يومك الحالي'
        : status == 'wait'
        ? 'فيه مهام تنتظرك'
        : 'قادم';
    final double hours = data.dayHours[d] ?? 0;
    final int pts = data.dayPoints[d] ?? 0;
    final int doneTasks = data.dayTasks[d] ?? 0;
    final int totalTasks = data.dayTotalTasks[d] ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'اليوم $d',
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                ),
              ),
              Text(statusLabel, style: TextStyle(color: palette.mute, fontSize: 13)),
            ],
          ),
          if (status != 'future' && status != 'rest') ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${hours.toStringAsFixed(1)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.tx)),
                      Text('ساعة دراسة', style: TextStyle(fontSize: 12, color: palette.mute)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('$pts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.tx)),
                      Text('نقطة', style: TextStyle(fontSize: 12, color: palette.mute)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('$doneTasks من $totalTasks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.tx)),
                      Text('مهام منجزة', style: TextStyle(fontSize: 12, color: palette.mute)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (status == 'future')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'لم يبدأ بعد. تظهر تفاصيله عندما يحين موعده.',
                style: TextStyle(color: palette.mute, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Study hours
// ---------------------------------------------------------------------------

class _StudyHoursSection extends StatelessWidget {
  const _StudyHoursSection({required this.data});
  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final double total = data.splitHours.values.fold<double>(0, (a, b) => a + b);
    final List<_SplitRow> rows = <_SplitRow>[
      _SplitRow('حضور الفيديوهات', data.splitHours['attend'] ?? 0, const Color(0xFF7CCBB0)),
      _SplitRow('الدراسة', data.splitHours['study'] ?? 0, const Color(0xFFE8B65A)),
      _SplitRow('حل الأسئلة', data.splitHours['questions'] ?? 0, const Color(0xFF93A1B8)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'ساعات الدراسة',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
        Text(
          'الوقت الذي سجّله مؤقت التركيز فعلياً.',
          style: TextStyle(color: palette.mute, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.card,
            border: Border.all(color: palette.line),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${data.totalFocusHours.floor()}',
                    style: TextStyle(
                      fontFamily: KTypography.displayFamily,
                      fontSize: 48,
                      color: palette.tx,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ساعة و ${(data.totalFocusHours * 60 % 60).round()} دقيقة',
                    style: TextStyle(color: palette.mute, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: rows
                        .map(
                          (_SplitRow r) => Expanded(
                            flex: (r.hours * 1000).round().clamp(1, 100000),
                            child: Container(color: r.color),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...rows.map((_SplitRow r) {
                final double pct = total > 0 ? r.hours / total : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: r.color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(r.label, style: TextStyle(color: palette.tx, fontSize: 14)),
                        ],
                      ),
                      Text(
                        '${r.hours.toStringAsFixed(1)} س',
                        style: TextStyle(color: palette.mute, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _SplitRow {
  const _SplitRow(this.label, this.hours, this.color);
  final String label;
  final double hours;
  final Color color;
}

// ---------------------------------------------------------------------------
// Subjects
// ---------------------------------------------------------------------------

class _SubjectsSection extends StatelessWidget {
  const _SubjectsSection({required this.data});
  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'التقدم في المواد',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
        Text(
          'نسبة المهام المنجزة في كل مادة.',
          style: TextStyle(color: palette.mute, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.card,
            border: Border.all(color: palette.line),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: data.subjects
                .map((SubjectProgress s) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(s.name, style: TextStyle(color: palette.tx, fontSize: 14)),
                              Text(
                                '${s.completedTasks} من ${s.totalTasks} مهمة · ${(s.percent * 100).round()}%',
                                style: TextStyle(color: palette.mute, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: s.percent,
                              minHeight: 8,
                              backgroundColor: palette.line,
                              valueColor: AlwaysStoppedAnimation<Color>(s.color),
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Badge painter
// ---------------------------------------------------------------------------

class _BadgePainter extends CustomPainter {
  const _BadgePainter({required this.tier, required this.icon});
  final int tier; // -1 none, 0..4
  final String icon;

  static const List<List<Color>> _tiers = <List<Color>>[
    <Color>[Color(0xFFB9753F), Color(0xFFE8BE92)],
    <Color>[Color(0xFF8E9BAD), Color(0xFFE6EBF2)],
    <Color>[Color(0xFFD9A441), Color(0xFFF8E3A6)],
    <Color>[Color(0xFF2FA37F), Color(0xFFB1EAD6)],
    <Color>[Color(0xFF4F93F0), Color(0xFFCDE5FF)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final bool earned = tier >= 0;
    final Offset c = Offset(size.width / 2, size.height * 0.4);
    final double r = size.width * 0.42;
    // ribbons
    final Paint ribbon = Paint()
      ..color = earned ? const Color(0xFFB52A20) : const Color(0xFFD9D2C3);
    final Path leftRibbon = Path()
      ..moveTo(c.dx - r * 0.5, c.dy + r * 0.6)
      ..lineTo(c.dx - r * 0.3, c.dy + r * 1.6)
      ..lineTo(c.dx - r * 0.9, c.dy + r * 1.4)
      ..close();
    final Path rightRibbon = Path()
      ..moveTo(c.dx + r * 0.5, c.dy + r * 0.6)
      ..lineTo(c.dx + r * 0.3, c.dy + r * 1.6)
      ..lineTo(c.dx + r * 0.9, c.dy + r * 1.4)
      ..close();
    canvas.drawPath(leftRibbon, ribbon);
    canvas.drawPath(rightRibbon, ribbon..color = ribbon.color.withValues(alpha: 0.85));

    // outer circle
    final Paint outer = Paint()
      ..shader = earned
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _tiers[tier],
            ).createShader(Rect.fromCircle(center: c, radius: r))
          : null
      ..color = earned ? Colors.transparent : const Color(0xFFD9D2C3);
    if (earned) {
      canvas.drawCircle(c, r, outer);
    } else {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFD9D2C3));
    }
    // inner circle
    canvas.drawCircle(
      c,
      r * 0.83,
      Paint()
        ..color = earned ? _tiers[tier][1] : const Color(0xFFF6F2EA)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      r * 0.83,
      Paint()
        ..color = earned ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF5B6A80).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // icon (simple)
    final Paint iconPaint = Paint()
      ..color = earned ? const Color(0xFF0D1A2D) : const Color(0xFF5B6A80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(c.dx - r * 0.5, c.dy - r * 0.5);
    canvas.scale(r / 28.0);
    _drawIcon(canvas, icon, iconPaint);
    canvas.restore();
  }

  void _drawIcon(Canvas canvas, String icon, Paint p) {
    switch (icon) {
      case 'flame':
        final Path path = Path()
          ..moveTo(12, 3)
          ..cubicTo(13, 6.5, 17, 8.5, 17, 13)
          ..arcToPoint(const Offset(7, 13), radius: const Radius.circular(5))
          ..cubicTo(7, 11, 8, 10, 9, 9)
          ..cubicTo(9, 11, 10, 12, 11, 12)
          ..cubicTo(11, 9, 10, 6, 12, 3);
        canvas.drawPath(path, p..style = PaintingStyle.fill);
        break;
      case 'star':
        final Path path = Path()
          ..moveTo(12, 3.5)
          ..lineTo(14.6, 8.9)
          ..lineTo(20.5, 9.7)
          ..lineTo(16.2, 13.8)
          ..lineTo(17.2, 19.7)
          ..lineTo(12, 16.9)
          ..lineTo(6.8, 19.7)
          ..lineTo(7.8, 13.8)
          ..lineTo(3.5, 9.7)
          ..lineTo(9.4, 8.9)
          ..close();
        canvas.drawPath(path, p..style = PaintingStyle.fill);
        break;
      default:
        canvas.drawCircle(const Offset(12, 12), 8, p..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _BadgePainter oldDelegate) {
    return oldDelegate.tier != tier || oldDelegate.icon != icon;
  }
}

class _HexagonPattern extends StatelessWidget {
  const _HexagonPattern();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _HexagonPainter());
  }
}

class _HexagonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF93A1B8).withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const double w = 56;
    const double h = 96;
    for (double y = -h; y < size.height + h; y += h) {
      for (double x = -w; x < size.width + w; x += w) {
        _drawHexagon(canvas, Offset(x, y), w / 2, paint);
        _drawHexagon(canvas, Offset(x + w / 2, y + h / 2), w / 2, paint);
      }
    }
  }

  void _drawHexagon(Canvas canvas, Offset c, double r, Paint paint) {
    final Path path = Path();
    for (int i = 0; i < 6; i++) {
      final double angle = (math.pi / 3) * i - math.pi / 2;
      final Offset p = Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
