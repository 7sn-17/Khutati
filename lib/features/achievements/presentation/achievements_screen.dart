// Achievements — a line-for-line rebuild of design/achievements_reference.html.
//
// Every measurement below is taken from that file, not from the app's general
// design tokens: the reference has its own scale (60px numerals, 22px section
// titles, a 56x96 hexagon tile, a 50px week label column). Keeping the numbers
// local and documenting the CSS rule they come from is what makes it possible
// to diff this file against the reference by eye.
//
// Nothing here is approximated with stock Material widgets: the hexagon hero
// texture, the check marks, the dashed circles and the five medals with their
// ribbons are all painted from the reference's SVG geometry.

import 'dart:math' as math;
import 'dart:ui' show MaskFilter, PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/surfaces.dart';
import '../../../l10n/l10n.dart';
import '../application/achievements_controller.dart';

// ---------------------------------------------------------------------------
// Values lifted verbatim from design/achievements_reference.html
// ---------------------------------------------------------------------------

/// `.hero { background:#0D1A2D; color:#EAE5DA; border-radius:28px;
///          padding:22px 20px 18px; gap:16px }`
///
/// Only the dark surface is taken from the reference; every foreground colour
/// inside the hero comes from the theme palette, because the reference is
/// dark-only and a light-mode build needs dark text on the cream surface.
const Color _heroBg = Color(0xFF0D1A2D);

/// `.hero > .pat` opacity. Kept exactly as the reference; only the line colour
/// follows the theme.
const double _hexAlpha = 0.13;

/// `.wrap { padding:16px 16px 120px; gap:30px }`
const EdgeInsets _wrapPadding = EdgeInsets.fromLTRB(16, 16, 16, 120);
const double _sectionGap = 30;

/// `.hero .trk { background:#26395A }`, `.trk { height:8px; border-radius:4px }`
const double _trackHeight = 8;
const double _trackRadius = 4;

/// `h1 { font-size:30px }`, `h2 { font-size:21px }`, `h3 { font-size:18px }`
const double _h1Size = 30;
const double _h2Size = 21;
const double _h3Size = 18;

/// `.big { font-size:60px; line-height:1.1 }`
const double _bigSize = 60;

/// `.cat { border-radius:22px; padding:14px; grid-template-columns:84px 1fr;
///         gap:4px 14px }`
const double _badgeRadius = 22;
const double _medalWidth = 84;

/// `.surf { border-radius:22px; padding:16px }`
const double _surfaceRadius = 22;

/// Medals: five tiers, metals and progress thresholds exactly as the reference.
const List<String> _tierNames = <String>[
  'برونزي',
  'فضي',
  'ذهبي',
  'زمردي',
  'ماسي',
];
const List<List<Color>> _tierColors = <List<Color>>[
  <Color>[Color(0xFFB9753F), Color(0xFFE8BE92)],
  <Color>[Color(0xFF8E9BAD), Color(0xFFE6EBF2)],
  <Color>[Color(0xFFD9A441), Color(0xFFF8E3A6)],
  <Color>[Color(0xFF2FA37F), Color(0xFFB1EAD6)],
  <Color>[Color(0xFF4F93F0), Color(0xFFCDE5FF)],
];

/// `WD=[...]`, `WS=[...]`, `MO=[...]` from the reference.
const List<String> _weekdayFull = <String>[
  'الأحد',
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
];
const List<String> _weekdayShort = <String>[
  'أحد',
  'اثنين',
  'ثلاثاء',
  'أربعاء',
  'خميس',
  'جمعة',
  'سبت',
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

/// `fa = n => n.toLocaleString('en-US')` — Latin digits with thousands
/// separators, because the reference prints `1,250` rather than `١٬٢٥٠`.
String _fa(num value) {
  final String digits = value.abs().toStringAsFixed(0);
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return value < 0 ? '-$out' : out.toString();
}

/// `hm = h => ...` — "2 س و30 د" / "45 د".
String _duration(double hours) {
  final int whole = hours.floor();
  final int minutes = ((hours - whole) * 60).round();
  if (whole <= 0) return '$minutes د';
  return minutes > 0 ? '$whole س و$minutes د' : '$whole س';
}

/// `dateOf(d)` from the reference, resolved against the real plan start.
DateTime? _dateOfDay(AchievementsData data, int day) {
  final DateTime? start = data.planStart;
  if (start == null) return null;
  return DateTime(
    start.year,
    start.month,
    start.day,
  ).add(Duration(days: day - 1));
}

/// `WD[dateOf(d).getDay()]` — Dart starts the week on Monday, the reference on
/// Sunday, so Sunday (7) must map back to index 0.
int _weekdayIndex(DateTime date) => date.weekday % 7;

String _fullDate(DateTime date) =>
    '${_weekdayFull[_weekdayIndex(date)]} ${date.day} ${_months[date.month - 1]}';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AchievementsData?> data = ref.watch(achievementsProvider);
    return data.when(
      loading: () => Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '$error',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              color: context.palette.mute,
            ),
          ),
        ),
      ),
      data: (AchievementsData? d) {
        if (d == null) {
          return Center(child: Text(context.l10n.achievementsPlaceholder));
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

  void _selectDay(int day) {
    if (_selectedDay == day) return;
    setState(() => _selectedDay = day);
  }

  @override
  Widget build(BuildContext context) {
    final AchievementsData d = widget.data;
    final KhutatiPalette palette = context.palette;

    return ListView(
      padding: _wrapPadding,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text(
            'إنجازاتي',
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: _h1Size,
              fontWeight: FontWeight.w700,
              color: palette.tx,
              height: 1.3,
            ),
          ),
        ),
        SizedBox(height: _sectionGap),
        _HeroCard(data: d),
        SizedBox(height: _sectionGap),
        _BadgesSection(data: d),
        SizedBox(height: _sectionGap),
        _DayMapSection(
          data: d,
          selectedDay: _selectedDay ?? d.todayDayNumber,
          onSelect: _selectDay,
        ),
        SizedBox(height: _sectionGap),
        _StudyHoursSection(data: d),
        SizedBox(height: _sectionGap),
        _SubjectsSection(data: d),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero card
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    // The hero follows the theme: the reference's navy card in dark mode, a
    // warm raised card in light mode. Painting the navy card in light mode is
    // what made the themed (dark) hero text unreadable.
    final KhutatiPalette palette = context.palette;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: kCardShadow(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: dark ? _heroBg : palette.card,
                borderRadius: BorderRadius.circular(28),
                border: dark ? null : Border.all(color: palette.line),
              ),
            ),
            // `.hero > .pat { position:absolute; inset:0 }`
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _HexPattern(
                      palette.mute.withValues(alpha: _hexAlpha),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 12, child: _PointsColumn(data: data)),
                      SizedBox(width: 16),
                      Expanded(flex: 10, child: _StreakColumn(data: data)),
                    ],
                  ),
                  SizedBox(height: 16),
                  _WeekStrip(data: data),
                  SizedBox(height: 16),
                  _NextBadgeBlock(data: data),
                  _HowItWorks(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointsColumn extends StatelessWidget {
  const _PointsColumn({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'إجمالي نقاطك',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
            height: 1.6,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            _fa(data.totalPoints),
            maxLines: 1,
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: _bigSize,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: palette.gold,
            ),
          ),
        ),
        Container(
          margin: EdgeInsets.only(top: 6),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: palette.gold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '+${data.pointsToday} نقطة اليوم',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              color: palette.gold,
            ),
          ),
        ),
      ],
    );
  }
}

class _StreakColumn extends StatelessWidget {
  const _StreakColumn({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'سلسلتك',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
            height: 1.6,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            _fa(data.streak),
            maxLines: 1,
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: _bigSize,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: palette.tx,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'أيام متتالية من الإنجاز',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 14,
              color: palette.mute,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

/// `.week` — seven dots, one per day, with `.dot.done/.rest/.wait/.today`.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final DateTime? today = data.todayDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'آخر 7 أيام',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: palette.tx,
            height: 1.6,
          ),
        ),
        SizedBox(height: 10),
        Row(
          children: <Widget>[
            for (int i = 0; i < 7; i++)
              Expanded(
                child: _DayDot(
                  status: i < data.last7.length ? data.last7[i] : 'future',
                  isToday: i == data.last7.length - 1,
                  date: today == null
                      ? null
                      : DateTime(
                          today.year,
                          today.month,
                          today.day,
                        ).subtract(Duration(days: 6 - i)),
                ),
              ),
          ],
        ),
        SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: <Widget>[
            _LegendDot(color: palette.ok, filled: true, label: 'أنجزت يومك'),
            _LegendDot(dashed: true, label: 'يوم راحة'),
            _LegendDot(color: palette.gold, label: 'مهام تنتظرك'),
          ],
        ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.status, required this.isToday, this.date});

  final String status;
  final bool isToday;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color line;
    final Color fill;
    final bool dashed;
    switch (status) {
      case 'done':
        line = palette.ok;
        fill = palette.ok;
        dashed = false;
      case 'rest':
        line = palette.line;
        fill = Colors.transparent;
        dashed = true;
      case 'wait':
        line = palette.gold;
        fill = Colors.transparent;
        dashed = false;
      case 'today':
        line = palette.tx;
        fill = palette.card;
        dashed = false;
      default:
        line = palette.line;
        fill = Colors.transparent;
        dashed = false;
    }

    final String label = isToday
        ? 'اليوم'
        : (date == null ? '' : _weekdayShort[_weekdayIndex(date!)]);

    return Column(
      children: <Widget>[
        SizedBox(
          width: 36,
          height: 36,
          child: CustomPaint(
            painter: _CirclePainter(
              color: line,
              fill: fill,
              strokeWidth: 2,
              dashed: dashed,
            ),
            child: Center(
              child: status == 'done'
                  ? _CheckMark(size: 16, color: palette.bg)
                  : status == 'rest'
                  ? Text(
                      '–',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.mute,
                        height: 1,
                      ),
                    )
                  : SizedBox.shrink(),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            height: 1.2,
            color: isToday ? palette.tx : palette.mute,
            fontWeight: isToday ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.label,
    this.color,
    this.filled = false,
    this.dashed = false,
  });

  final String label;
  final Color? color;
  final bool filled;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color dot = color ?? palette.mute;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 10,
          height: 10,
          child: CustomPaint(
            painter: _CirclePainter(
              color: dot,
              fill: filled ? dot : Colors.transparent,
              strokeWidth: 2,
              dashed: dashed,
            ),
          ),
        ),
        SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            color: palette.mute,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

/// `.next { border-top:1px solid #26395A; padding-top:14px; gap:8px }`
class _NextBadgeBlock extends StatelessWidget {
  const _NextBadgeBlock({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final BadgeInfo? next = data.nextBadge;
    if (next == null) {
      return Container(
        padding: EdgeInsets.only(top: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.line)),
        ),
        child: Text(
          'أكملت كل الأوسمة. أحسنت!',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.ok,
            height: 1.6,
          ),
        ),
      );
    }
    final int nextThreshold = next.nextThreshold ?? next.current;
    final int remaining = (nextThreshold - next.current).clamp(
      0,
      nextThreshold,
    );

    return Container(
      padding: EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  'وسامك القادم: ${_tierNames[next.level]} في ${next.name}',
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 14,
                    color: palette.tx,
                    height: 1.6,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '${_fa(next.current)} من ${_fa(nextThreshold)}',
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  color: palette.mute,
                  height: 1.6,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _Track(
            fraction: next.fraction,
            background: palette.line,
            fill: palette.gold,
          ),
          SizedBox(height: 8),
          Text(
            'يتبقّى ${_fa(remaining)} ${next.unit} فقط.',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              color: palette.mute,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// `<details>` — a 44px summary row with a rotating chevron and three rules.
class _HowItWorks extends StatefulWidget {
  const _HowItWorks();

  @override
  State<_HowItWorks> createState() => _HowItWorksState();
}

class _HowItWorksState extends State<_HowItWorks> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
      ),
      padding: EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: SizedBox(
              height: 44,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'كيف تُحسب النقاط والسلسلة؟',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 14,
                        color: palette.tx,
                        height: 1.6,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: Duration(milliseconds: 200),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: palette.tx.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: _Chevron(size: 16, color: palette.tx),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _Bullet(
                          'كل فيديو تكمله يمنحك 10 نقاط، وحل أسئلة الفصل يمنحك 20 نقطة.',
                        ),
                        _Bullet(
                          'السلسلة هي عدد الأيام المتتالية التي أنجزت فيها مهامك. يوم الراحة المجدول لا يقطعها.',
                        ),
                        _Bullet(
                          'إن فاتك يوم تبدأ سلسلة جديدة، ولا تفقد نقاطك ولا أوسمتك.',
                        ),
                      ],
                    ),
                  )
                : SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: 2, left: 6, right: 6),
            child: Text(
              '•',
              style: TextStyle(color: palette.mute, fontSize: 14, height: 1.6),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 14,
                color: palette.mute,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    final int earned = data.badges.fold<int>(
      0,
      (int sum, BadgeInfo badge) => sum + badge.level,
    );
    final int all = data.badges.length * 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'الأوسمة',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: _h2Size,
            fontWeight: FontWeight.w700,
            color: palette.tx,
            height: 1.5,
          ),
        ),
        Text(
          'جمعت $earned وسام من $all. لكل فئة خمسة مستويات: '
          'برونزي، فضي، ذهبي، زمردي، ماسي.',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
            height: 1.6,
          ),
        ),
        SizedBox(height: 14),
        for (int i = 0; i < data.badges.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == data.badges.length - 1 ? 0 : 12,
            ),
            child: _BadgeCard(badge: data.badges[i]),
          ),
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
    final int level = badge.level;
    final int? next = badge.nextThreshold;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_badgeRadius),
        boxShadow: kCardShadow(context),
      ),
      child: Material(
        color: palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_badgeRadius),
          side: BorderSide(color: palette.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(_badgeRadius),
          onTap: () => _openBadgeSheet(context, badge),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: _medalWidth,
                      child: _Medal(icon: badge.icon, level: level),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            badge.name,
                            style: TextStyle(
                              fontFamily: KTypography.displayFamily,
                              fontSize: _h3Size,
                              fontWeight: FontWeight.w700,
                              color: palette.tx,
                              height: 1.4,
                            ),
                          ),
                          level == 0
                              ? Text(
                                  'لم تبدأ بعد',
                                  style: TextStyle(
                                    fontFamily: KTypography.bodyFamily,
                                    fontSize: 13,
                                    color: palette.mute,
                                    height: 1.6,
                                  ),
                                )
                              : Text.rich(
                                  TextSpan(
                                    children: <InlineSpan>[
                                      TextSpan(text: 'المستوى '),
                                      TextSpan(
                                        text: _tierNames[level - 1],
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: palette.tx,
                                        ),
                                      ),
                                      TextSpan(text: ' ($level من 5)'),
                                    ],
                                  ),
                                  style: TextStyle(
                                    fontFamily: KTypography.bodyFamily,
                                    fontSize: 13,
                                    color: palette.mute,
                                    height: 1.6,
                                  ),
                                ),
                          SizedBox(height: 6),
                          if (next == null)
                            Text(
                              'أنهيت كل المستويات. أحسنت!',
                              style: TextStyle(
                                fontFamily: KTypography.bodyFamily,
                                fontSize: 13,
                                color: palette.ok,
                                height: 1.6,
                              ),
                            )
                          else ...<Widget>[
                            _Track(
                              fraction: badge.fraction,
                              background: palette.line,
                              fill: palette.gold,
                              minFraction: 0.03,
                            ),
                            SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  '${_fa(badge.current)} من ${_fa(next)} ${badge.unit}',
                                  style: TextStyle(
                                    fontFamily: KTypography.bodyFamily,
                                    fontSize: 12,
                                    color: palette.mute,
                                    height: 1.6,
                                  ),
                                ),
                                Text(
                                  'التالي: ${_tierNames[level]}',
                                  style: TextStyle(
                                    fontFamily: KTypography.bodyFamily,
                                    fontSize: 12,
                                    color: palette.mute,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // `.lad { grid-column:1/-1; border-top:1px solid var(--line);
                //         margin-top:8px; padding-top:12px }`
                Container(
                  margin: EdgeInsets.only(top: 8),
                  padding: EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: palette.line)),
                  ),
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < badge.thresholds.length; i++)
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              _Pip(index: i, earned: i < level),
                              SizedBox(height: 4),
                              Text(
                                _fa(badge.thresholds[i]),
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: 11,
                                  color: palette.mute,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.pip { width:30px; height:30px; border-radius:50%;
///         border:2px dashed var(--line) }`
/// `.pip.e { border:2px solid var(--c); background:var(--l); color:#0D1A2D }`
class _Pip extends StatelessWidget {
  const _Pip({required this.index, required this.earned});

  final int index;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final List<Color> tier = _tierColors[index];
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(
        painter: _CirclePainter(
          color: earned ? tier[0] : palette.line,
          fill: earned ? tier[1] : Colors.transparent,
          strokeWidth: 2,
          dashed: !earned,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 12,
              height: 1.1,
              fontWeight: earned ? FontWeight.w500 : FontWeight.w400,
              color: earned ? Color(0xFF0D1A2D) : palette.mute,
            ),
          ),
        ),
      ),
    );
  }
}

/// `.box { border-radius:28px 28px 0 0; padding:20px 20px 24px }`
void _openBadgeSheet(BuildContext context, BadgeInfo badge) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final KhutatiPalette palette = sheetContext.palette;
      final int level = badge.level;
      final int current = badge.current;

      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.card,
            border: Border.all(color: palette.line),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            24 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 110,
                  child: _Medal(icon: badge.icon, level: level),
                ),
                SizedBox(height: 6),
                Text(
                  badge.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: _h2Size,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '${badge.name}. أنت الآن عند ${_fa(current)} ${badge.unit}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 14,
                    color: palette.mute,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: 8),
                // `.lr { grid-template-columns:30px 1fr auto; gap:12px;
                //        border-top:1px solid var(--line); padding:10px 0 }`
                for (int i = 0; i < badge.thresholds.length; i++)
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: palette.line)),
                    ),
                    child: Row(
                      children: <Widget>[
                        _Pip(index: i, earned: i < level),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _tierNames[i],
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: 14,
                                  color: palette.tx,
                                  height: 1.6,
                                ),
                              ),
                              Text(
                                '${_fa(badge.thresholds[i])} ${badge.unit}',
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: 12,
                                  color: palette.mute,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          i < level
                              ? 'مكتسب'
                              : i == level
                              ? 'تبقّى ${_fa(badge.thresholds[i] - current)}'
                              : 'قادم',
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: 12,
                            color: i < level ? palette.ok : palette.mute,
                            fontWeight: i < level
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: Size.fromHeight(48),
                      backgroundColor: palette.card2,
                      side: BorderSide(color: palette.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'إغلاق',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 16,
                        color: palette.tx,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Medal — SVG geometry from the reference, painted with Canvas
// ---------------------------------------------------------------------------

class _Medal extends StatelessWidget {
  const _Medal({required this.icon, required this.level});

  final String icon;
  final int level;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 100 / 118,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MedalPainter(
            icon: icon,
            level: level,
            line: context.palette.line,
            mute: context.palette.mute,
          ),
        ),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter({
    required this.icon,
    required this.level,
    required this.line,
    required this.mute,
  });

  final String icon;
  final int level;
  final Color line;
  final Color mute;

  static Color _ribbonTop = Color(0xFFD3453A);
  static Color _ribbonBottom = Color(0xFF8C1B13);

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 100;
    canvas.save();
    canvas.scale(scale);

    final bool earned = level > 0;
    final List<Color>? tier = earned ? _tierColors[level - 1] : null;
    Rect box = Rect.fromLTWH(0, 0, 100, 118);

    // ---- Ribbons -------------------------------------------------------
    // `<polygon points="28,70 50,78 42,116 31,106 20,114"/>` and its mirror at
    // `fill-opacity=".85"`. The reference paints both flat red; a vertical
    // gradient plus a darker right tail reads as folded satin at 84px without
    // changing a single anchor point.
    final Color ribbonTop = earned ? _ribbonTop : Color(0xFF9AA3AE);
    final Color ribbonBottom = earned ? _ribbonBottom : Color(0xFF6B7280);
    final Path leftRibbon = Path()
      ..moveTo(28, 70)
      ..lineTo(50, 78)
      ..lineTo(42, 116)
      ..lineTo(31, 106)
      ..lineTo(20, 114)
      ..close();
    canvas.drawPath(
      leftRibbon,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[ribbonTop, ribbonBottom],
        ).createShader(box),
    );
    final Path rightRibbon = Path()
      ..moveTo(72, 70)
      ..lineTo(50, 78)
      ..lineTo(58, 116)
      ..lineTo(69, 106)
      ..lineTo(80, 114)
      ..close();
    canvas.drawPath(
      rightRibbon,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(ribbonTop, Colors.black, 0.18)!,
            Color.lerp(ribbonBottom, Colors.black, 0.28)!,
          ],
        ).createShader(box),
    );
    // The crease where the two tails pass under the disc.
    canvas.drawPath(
      Path()
        ..moveTo(50, 78)
        ..lineTo(50, 118)
        ..lineTo(46, 118),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );

    // ---- Disc ----------------------------------------------------------
    // `<circle r="42" fill="tier[0] or var(--line)"/>` — the metal ring, swept
    // from the light top-left corner to the shadowed bottom-right.
    canvas.drawCircle(
      Offset(50, 48),
      42,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tier == null
              ? <Color>[Color(0xFFC8D0DA), Color(0xFFA8B0BC)]
              : <Color>[
                  tier[1],
                  tier[0],
                  Color.lerp(tier[0], Colors.black, 0.10)!,
                ],
          stops: <double>[0.0, 0.55, 1.0],
        ).createShader(box),
    );

    // `<circle r="35" fill="tier[1] or var(--card2)" stroke="#fff"
    //  stroke-opacity=".55" [stroke-dasharray="4 4"]/>` — the recessed face.
    canvas.drawCircle(
      Offset(50, 48),
      35,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tier == null
              ? <Color>[Color(0xFFF2F5F9), Color(0xFFDCE2EA)]
              : <Color>[
                  Color.lerp(tier[1], Colors.white, 0.50)!,
                  tier[1],
                  Color.lerp(tier[0], Colors.white, 0.15)!,
                ],
          stops: <double>[0.0, 0.5, 1.0],
        ).createShader(box),
    );

    if (tier != null) {
      // Specular sheen across the top of the face.
      canvas.drawArc(
        Rect.fromCircle(center: Offset(50, 48), radius: 26),
        math.pi * 1.08,
        math.pi * 0.42,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    final Paint inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = tier != null
          ? Colors.white.withValues(alpha: 0.55)
          : mute.withValues(alpha: 0.55);
    if (tier == null) {
      _drawDashedCircle(canvas, Offset(50, 48), 35, inner, dash: 4, gap: 4);
    } else {
      canvas.drawCircle(Offset(50, 48), 35, inner);
    }

    // ---- Icon ----------------------------------------------------------
    // `<g transform="translate(28 26) scale(1.83)" stroke-width="1.8">`: a
    // 24x24 box at 1.83x is 43.9 wide, so its centre lands on (28+22, 26+22) =
    // (50, 48) — exactly the face centre. The stroke is thickened to 2.1 so it
    // survives the 1.83x downscale as ~1.1px instead of hairlining out.
    canvas.save();
    canvas.translate(28, 26);
    canvas.scale(1.83);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = tier != null
          ? Color(0xFF0D1A2D).withValues(alpha: 0.86)
          : mute.withValues(alpha: 0.7);
    _paintIcon(canvas, icon, stroke);
    canvas.restore();

    canvas.restore();
  }

  /// `IC[ic]` — the five 24x24 icon paths, in order.
  void _paintIcon(Canvas canvas, String key, Paint paint) {
    switch (key) {
      case 'flame':
        // M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3
        // 0-3-1-6 1-9z
        final Path flame = Path()
          ..moveTo(12, 3)
          ..cubicTo(13, 6.5, 17, 8.5, 17, 13)
          ..arcToPoint(
            Offset(7, 13),
            radius: Radius.circular(5),
            clockwise: false,
          )
          ..cubicTo(7, 11, 8, 10, 9, 9)
          ..cubicTo(9, 11, 10, 12, 11, 12)
          ..cubicTo(11, 9, 10, 6, 12, 3)
          ..close();
        canvas.drawPath(flame, paint);
      case 'star':
        // m12 3.5 2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.9l-5.2 2.8 1-5.9
        // L3.5 9.7l5.9-.8z
        final Path star = Path()
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
        canvas.drawPath(star, paint);
      case 'clock':
        // <circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/>
        canvas.drawCircle(Offset(12, 12), 8, paint);
        canvas.drawPath(
          Path()
            ..moveTo(12, 7.5)
            ..lineTo(12, 12)
            ..lineTo(15, 14),
          paint,
        );
      case 'flag':
        // <path d="M6 21V4m0 1h11l-2 4 2 4H6"/>
        canvas.drawPath(
          Path()
            ..moveTo(6, 21)
            ..lineTo(6, 4)
            ..moveTo(6, 5)
            ..lineTo(17, 5)
            ..lineTo(15, 9)
            ..lineTo(17, 13)
            ..lineTo(6, 13),
          paint,
        );
      case 'quiz':
        // <circle cx="12" cy="12" r="9"/>
        // <path d="M9.3 9.3a2.8 2.8 0 1 1 4.3 2.4c-1 .6-1.6 1.2-1.6 2.3
        //         M12 17.3v.2"/>
        canvas.drawCircle(Offset(12, 12), 9, paint);
        canvas.drawPath(
          Path()
            ..moveTo(9.3, 9.3)
            ..arcToPoint(
              Offset(13.6, 11.7),
              radius: Radius.circular(2.8),
              clockwise: true,
            )
            ..cubicTo(12.6, 12.3, 12, 12.9, 12, 14)
            ..moveTo(12, 17.3)
            ..lineTo(12, 17.5),
          paint,
        );
      default:
        canvas.drawCircle(Offset(12, 12), 9, paint);
    }
  }

  @override
  bool shouldRepaint(_MedalPainter oldDelegate) =>
      oldDelegate.icon != icon ||
      oldDelegate.level != level ||
      oldDelegate.line != line ||
      oldDelegate.mute != mute;
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
  final int selectedDay;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final int total = data.totalDays;
    final int completed = data.completedDays;
    final double fraction = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'خريطة الأيام',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: _h2Size,
            fontWeight: FontWeight.w700,
            color: palette.tx,
            height: 1.5,
          ),
        ),
        Text(
          'كل مربع يوم من أيام الخطة. اضغط على أي يوم لترى تفاصيله.',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
            height: 1.6,
          ),
        ),
        SizedBox(height: 14),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '$completed يوماً مكتملاً من $total',
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 14,
                      color: palette.tx,
                      height: 1.6,
                    ),
                  ),
                  Text(
                    '${(fraction * 100).round()}%',
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 14,
                      color: palette.mute,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              _Track(
                fraction: fraction,
                background: palette.line,
                fill: palette.gold,
              ),
              SizedBox(height: 14),
              _DayGrid(
                data: data,
                selectedDay: selectedDay,
                onSelect: onSelect,
              ),
              SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _MapLegend(
                    color: palette.ok,
                    label: 'مكتمل',
                    fill: palette.ok,
                  ),
                  _MapLegend(
                    color: palette.gold,
                    label: 'تنتظرك',
                    borderWidth: 2,
                  ),
                  _MapLegend(color: palette.tx, label: 'اليوم', borderWidth: 2),
                  _MapLegend(
                    color: palette.mute,
                    label: 'راحة',
                    borderWidth: 1.5,
                    dashed: true,
                  ),
                  _MapLegend(
                    color: palette.line,
                    label: 'قادم',
                    fill: palette.card2,
                    borderWidth: 1,
                  ),
                ],
              ),
              SizedBox(height: 14),
              _DayDetail(data: data, day: selectedDay),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.data,
    required this.selectedDay,
    required this.onSelect,
  });

  final AchievementsData data;
  final int selectedDay;
  final ValueChanged<int> onSelect;

  /// Width of the week-label gutter. Only `أسبوع N` is shown now, so the gutter
  /// is narrow: every dp it takes is a dp the seven day cells lose, and cramped
  /// cells are what clipped the weekday headers.
  static const double _labelWidth = 40;
  static const double _gap = 5;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final int total = data.totalDays;
    final DateTime? start = data.planStart;

    // Column 0 is Sunday (the reference's `WD[0]`), so the first row has to be
    // padded by however many weekdays the plan's first day sits after Sunday.
    // Without this every cell would carry the wrong weekday as soon as the
    // plan does not start on a Sunday — which is what made the last week look
    // scrambled.
    final int offset = start == null ? 0 : _weekdayIndex(start);
    final int cells = offset + total;
    final int weeks = total <= 0 ? 0 : (cells / 7).ceil();
    final int currentWeek = data.todayDayNumber > 0
        ? (offset + data.todayDayNumber - 1) ~/ 7
        : 0;

    final List<Widget> rows = <Widget>[
      Row(
        spacing: _gap,
        children: <Widget>[
          SizedBox(width: _labelWidth),
          for (int i = 0; i < 7; i++)
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _weekdayShort[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 11,
                    color: i == offset && start != null
                        ? palette.tx
                        : palette.mute,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
      SizedBox(height: 6),
    ];

    for (int w = 0; w < weeks; w++) {
      rows.add(
        Row(
          spacing: _gap,
          children: <Widget>[
            SizedBox(
              width: _labelWidth,
              child: _WeekLabel(
                index: w,
                current: w == currentWeek,
                palette: palette,
              ),
            ),
            for (int c = 0; c < 7; c++)
              Expanded(child: _cellAt(w * 7 + c - offset + 1, total)),
          ],
        ),
      );
      if (w != weeks - 1) rows.add(SizedBox(height: _gap));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) => rows[index],
    );
  }

  /// One grid slot. Days outside `1..total` are leading/trailing blanks, so the
  /// last row ends where the plan ends instead of showing phantom days.
  Widget _cellAt(int day, int total) {
    if (day < 1 || day > total) return SizedBox.shrink();
    return _DayCell(
      day: day,
      total: total,
      status: data.dayStatus[day] ?? 'future',
      selected: selectedDay == day,
      onTap: onSelect,
    );
  }
}

/// `أسبوع 3` — the week number only. The date range that used to sit under it
/// was removed at the product owner's request; the weekday headers above each
/// column already carry the real dates.
class _WeekLabel extends StatelessWidget {
  const _WeekLabel({
    required this.index,
    required this.current,
    required this.palette,
  });

  final int index;
  final bool current;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    // The gutter is narrow, so `أسبوع 10` scales down instead of ellipsising.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        'أسبوع ${index + 1}',
        maxLines: 1,
        style: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: 11,
          height: 1.35,
          color: current ? palette.tx : palette.mute,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.total,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final int total;
  final String status;
  final bool selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (day > total) return SizedBox.shrink();

    final KhutatiPalette palette = context.palette;
    final bool done = status == 'done';
    final bool wait = status == 'wait';
    final bool today = status == 'today';
    final bool rest = status == 'rest';

    final Color background = done
        ? palette.ok
        : today
        ? palette.card
        : palette.card2;
    final Color border = done
        ? palette.ok
        : wait
        ? palette.gold
        : today
        ? palette.tx
        : rest
        ? palette.mute
        : palette.line;
    final double borderWidth = wait || today
        ? 2.5
        : rest
        ? 1.5
        : 1.5;
    final Color text = done
        ? palette.bg
        : wait || today
        ? palette.tx
        : palette.mute;

    return GestureDetector(
      onTap: () => onTap(day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.gold : Colors.transparent,
            width: 2,
          ),
        ),
        padding: EdgeInsets.all(1),
        child: AspectRatio(
          aspectRatio: 1,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _CellPainter(
                fill: background,
                border: border,
                borderWidth: borderWidth,
                dashed: rest,
              ),
              child: Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 12,
                    height: 1.2,
                    color: text,
                    fontWeight: today ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({
    required this.color,
    required this.label,
    this.fill = Colors.transparent,
    this.borderWidth = 0,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final Color fill;
  final double borderWidth;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: borderWidth > 0 && !dashed
                ? Border.all(color: color, width: borderWidth)
                : dashed
                ? Border.all(color: color, width: borderWidth)
                : null,
          ),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            color: palette.mute,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

/// `.dd { background:var(--card2); border-radius:14px; padding:12px 14px;
///        min-height:96px; margin-top:14px }`
class _DayDetail extends StatelessWidget {
  const _DayDetail({required this.data, required this.day});

  final AchievementsData data;
  final int day;

  static Map<String, String> _statusLabel = <String, String>{
    'done': 'مكتمل',
    'wait': 'فيه مهام تنتظرك',
    'today': 'يومك الحالي',
    'rest': 'يوم راحة مجدول',
    'future': 'قادم',
  };

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final String status = data.dayStatus[day] ?? 'future';
    final DateTime? date = _dateOfDay(data, day);
    final double hours = data.dayHours[day] ?? 0;
    final int points = data.dayPoints[day] ?? 0;
    final int tasks = data.dayTasks[day] ?? 0;
    final int totalTasks = data.dayTotalTasks[day] ?? 0;

    return Container(
      constraints: BoxConstraints(minHeight: 96),
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                'اليوم $day',
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: palette.tx,
                  height: 1.5,
                ),
              ),
              Spacer(),
              Text(
                date == null ? '' : _fullDate(date),
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  color: palette.mute,
                  height: 1.5,
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '${_statusLabel[status] ?? ''}'
              '${status == 'rest' ? '. لا يقطع سلسلتك.' : ''}',
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 14,
                color: palette.mute,
                height: 1.6,
              ),
            ),
          ),
          if (status == 'future')
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'لم يبدأ بعد. تظهر تفاصيله عندما يحين موعده.',
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  color: palette.mute,
                  height: 1.6,
                ),
              ),
            )
          else if (status != 'rest')
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _DetailStat(value: _duration(hours), label: 'دراسة'),
                  ),
                  Expanded(
                    child: _DetailStat(value: _fa(points), label: 'نقطة'),
                  ),
                  Expanded(
                    child: _DetailStat(
                      value: '$tasks من $totalTasks',
                      label: 'مهام منجزة',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: palette.tx,
            height: 1.4,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            color: palette.mute,
            height: 1.4,
          ),
        ),
      ],
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
    final double total = data.totalFocusHours;
    final double attend = data.splitHours['attend'] ?? 0;
    final double study = data.splitHours['study'] ?? 0;
    final double questions = data.splitHours['questions'] ?? 0;
    final double sum = attend + study + questions;

    int flex(double value) =>
        sum <= 0 ? 0 : math.max(1, (value / sum * 1000).round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'ساعات الدراسة',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: _h2Size,
            fontWeight: FontWeight.w700,
            color: palette.tx,
            height: 1.5,
          ),
        ),
        Text(
          'الوقت الذي سجّله مؤقت التركيز فعلياً.',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
            height: 1.6,
          ),
        ),
        SizedBox(height: 14),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${total.floor()}',
                    style: TextStyle(
                      fontFamily: KTypography.displayFamily,
                      fontSize: 48,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: palette.tx,
                    ),
                  ),
                  SizedBox(width: 8),
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'ساعة و${((total % 1) * 60).round()} دقيقة',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 14,
                        color: palette.mute,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              // `.bar { height:14px; border-radius:7px; gap:2px }`
              Container(
                height: 14,
                decoration: BoxDecoration(
                  color: palette.line,
                  borderRadius: BorderRadius.circular(7),
                ),
                clipBehavior: Clip.antiAlias,
                child: sum <= 0
                    ? SizedBox.shrink()
                    : Row(
                        spacing: 2,
                        children: <Widget>[
                          if (attend > 0)
                            Expanded(
                              flex: flex(attend),
                              child: ColoredBox(color: palette.ok),
                            ),
                          if (study > 0)
                            Expanded(
                              flex: flex(study),
                              child: ColoredBox(color: palette.gold),
                            ),
                          if (questions > 0)
                            Expanded(
                              flex: flex(questions),
                              child: ColoredBox(color: palette.mute),
                            ),
                        ],
                      ),
              ),
              SizedBox(height: 12),
              _SplitRow(
                color: palette.ok,
                label: 'حضور الفيديوهات',
                value: _duration(attend),
              ),
              _SplitRow(
                color: palette.gold,
                label: 'الدراسة',
                value: _duration(study),
              ),
              _SplitRow(
                color: palette.mute,
                label: 'حل الأسئلة',
                value: _duration(questions),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  color: palette.tx,
                  height: 1.6,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 14,
              color: palette.tx,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subject progress
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
            fontSize: _h2Size,
            fontWeight: FontWeight.w700,
            color: palette.tx,
            height: 1.5,
          ),
        ),
        Text(
          'نسبة المهام المنجزة في كل مادة.',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
            height: 1.6,
          ),
        ),
        SizedBox(height: 14),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < data.subjects.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == data.subjects.length - 1 ? 0 : 14,
                  ),
                  child: _SubjectRow(subject: data.subjects[i]),
                ),
              if (data.subjects.isEmpty)
                Text(
                  'لا توجد مواد في الخطة بعد.',
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 14,
                    color: palette.mute,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject});

  final SubjectProgress subject;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              subject.name,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 14,
                color: palette.tx,
                height: 1.6,
              ),
            ),
            Text(
              '${subject.completedTasks} من ${subject.totalTasks} مهمة · '
              '${(subject.percent * 100).round()}%',
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 14,
                color: palette.mute,
                height: 1.6,
              ),
            ),
          ],
        ),
        SizedBox(height: 6),
        _Track(
          fraction: subject.percent,
          background: palette.line,
          fill: subject.color,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

/// `.surf { background:var(--card); border:1px solid var(--line);
///          border-radius:22px; padding:16px }`
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(_surfaceRadius),
      ),
      padding: EdgeInsets.all(16),
      child: child,
    );
  }
}

/// `.trk { height:8px; border-radius:4px; background:var(--line) }
///  .trk i { display:block; height:100%; border-radius:4px }`
class _Track extends StatelessWidget {
  const _Track({
    required this.fraction,
    required this.background,
    required this.fill,
    this.minFraction = 0,
  });

  final double fraction;
  final Color background;
  final Color fill;
  final double minFraction;

  @override
  Widget build(BuildContext context) {
    final double value = fraction.isFinite
        ? fraction.clamp(0.0, 1.0).toDouble()
        : 0;
    final double widthFactor = value <= 0
        ? 0
        : math.max(value, minFraction).clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(_trackRadius),
      child: SizedBox(
        height: _trackHeight,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: background),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                heightFactor: 1,
                child: ColoredBox(color: fill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `border-radius:50%` with optional dash pattern, for `.dot`, `.pip` and `.lg i`.
class _CirclePainter extends CustomPainter {
  const _CirclePainter({
    required this.color,
    required this.fill,
    required this.strokeWidth,
    this.dashed = false,
  });

  final Color color;
  final Color fill;
  final double strokeWidth;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);
    if (fill != Colors.transparent) {
      canvas.drawCircle(center, radius, Paint()..color = fill);
    }
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    if (dashed) {
      _drawDashedCircle(canvas, center, radius, stroke, dash: 3, gap: 3);
    } else {
      canvas.drawCircle(center, radius, stroke);
    }
  }

  @override
  bool shouldRepaint(_CirclePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.fill != fill ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashed != dashed;
}

/// `.cl { border-radius:10px; border:1.5px solid var(--line) }` plus the four
/// state variants from the reference's day-map CSS.
class _CellPainter extends CustomPainter {
  const _CellPainter({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.dashed,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = fill);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = border;
    if (dashed) {
      _drawDashedRRect(canvas, rect.deflate(borderWidth / 2), stroke);
    } else {
      canvas.drawRRect(rect.deflate(borderWidth / 2), stroke);
    }
  }

  @override
  bool shouldRepaint(_CellPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.dashed != dashed;
}

/// The hero texture: `<pattern id="pt" width="56" height="96">` with five
/// `<use>` calls of `M28 0 56 16V48L28 64 0 48V16z`, stroked #93A1B8 at 13%.
class _HexPattern extends CustomPainter {
  const _HexPattern(this.color);

  /// Reference opacity, unchanged. Only the hue follows the theme so the
  /// texture stays visible on the warm light card instead of washing out.
  final Color color;

  static double _tileWidth = 56;
  static double _tileHeight = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    final Path hex = Path()
      ..moveTo(28, 0)
      ..lineTo(56, 16)
      ..lineTo(56, 48)
      ..lineTo(28, 64)
      ..lineTo(0, 48)
      ..lineTo(0, 16)
      ..close();

    for (
      double y = -_tileHeight;
      y < size.height + _tileHeight;
      y += _tileHeight
    ) {
      for (
        double x = -_tileWidth;
        x < size.width + _tileWidth;
        x += _tileWidth
      ) {
        for (final Offset offset in <Offset>[
          Offset(x, y),
          Offset(x + 28, y + 48),
          Offset(x - 28, y + 48),
          Offset(x + 28, y - 48),
          Offset(x - 28, y - 48),
        ]) {
          canvas.save();
          canvas.translate(offset.dx, offset.dy);
          canvas.drawPath(hex, stroke);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HexPattern oldDelegate) => oldDelegate.color != color;
}

/// `m5 12.5 4.5 4.5L19 7.5` with `stroke-width="3"`, 16x16.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CheckPainter(color: color)),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 24;
    canvas.scale(scale);
    canvas.drawPath(
      Path()
        ..moveTo(5, 12.5)
        ..lineTo(9.5, 17)
        ..lineTo(19, 7.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.color != color;
}

/// `<path d="m6 9 6 6 6-6"/>` — the details chevron.
class _Chevron extends StatelessWidget {
  const _Chevron({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ChevronPainter(color: color)),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(
      Path()
        ..moveTo(6, 9)
        ..lineTo(12, 15)
        ..lineTo(18, 9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Dash helpers
// ---------------------------------------------------------------------------

void _drawDashedCircle(
  Canvas canvas,
  Offset center,
  double radius,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  final double circumference = 2 * math.pi * radius;
  final double step = dash + gap;
  final int segments = (circumference / step).floor();
  final double sweep = (dash / radius);
  for (int i = 0; i < segments; i++) {
    final double start = i * step / radius;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      paint,
    );
  }
}

void _drawDashedRRect(Canvas canvas, RRect rect, Paint paint) {
  final Path path = Path()..addRRect(rect);
  for (final PathMetric metric in path.computeMetrics()) {
    double distance = 0;
    while (distance < metric.length) {
      final double next = math.min(distance + 4, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + 3;
    }
  }
}
