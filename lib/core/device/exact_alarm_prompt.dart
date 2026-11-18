import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/widgets/controls.dart';
import '../design/widgets/dialogs.dart';
import 'exact_alarm_permission.dart';

/// Guards against stacking the same dialog from three entry points (startup,
/// the Focus tab, and a Settings toggle) and against re-asking a user who
/// already tapped "لاحقاً" in this process.
bool _prompted = false;
bool _showing = false;

/// Shows the "Alarms & reminders" dialog when exact alarms are denied.
///
/// Safe to call from any `initState` or tap handler:
///
/// * returns `false` immediately when the permission is already granted;
/// * never opens a second copy while one is visible;
/// * asks at most once per process unless [force] is set, which is what the
///   Settings toggles use because turning a reminder on is an explicit intent.
///
/// Returns `true` when the system settings screen was opened.
Future<bool> maybePromptExactAlarms(
  BuildContext context, {
  bool force = false,
}) async {
  if (_showing || !context.mounted) return false;
  // The platform check is async; the caller can be disposed while it runs, so
  // every await is followed by a mounted check before touching the context.
  if (await ExactAlarmPermission.canSchedule()) return false;
  if (!context.mounted) return false;
  if (!force && _prompted) return false;

  _showing = true;
  _prompted = true;
  try {
    return await showExactAlarmDialog(context);
  } finally {
    _showing = false;
  }
}

/// The one premium explanation for Android's "Alarms & reminders" grant.
///
/// Returns `true` when the system settings screen was opened. The caller can
/// re-check [ExactAlarmPermission.canSchedule] after the app resumes.
Future<bool> showExactAlarmDialog(BuildContext context) async {
  final bool? open = await showKDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => KDialog(
      eyebrow: 'صلاحية مطلوبة',
      title: 'المنبهات والتذكيرات',
      icon: Icons.alarm_rounded,
      message:
          'يحتاج مؤقت التركيز إلى صلاحية «المنبهات والتذكيرات» ليطلق التنبيه '
          'في الثانية المحددة، حتى لو كان التطبيق مغلقاً أو الهاتف في وضع توفير '
          'الطاقة.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? const Color(0x22E8B65A)
              : const Color(0x148F6210),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ستنتقل إلى إعدادات النظام. اختر «السماح» بجانب '
                '«المنبهات والتذكيرات»، ثم عد إلى خطتي.',
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.smallSize,
                  height: 1.65,
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? const Color(0xFFEAE5DA)
                      : const Color(0xFF16233A),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <KDialogAction>[
        KDialogAction(
          label: 'فتح الإعدادات',
          icon: Icons.settings_rounded,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        KDialogAction(
          label: 'لاحقاً',
          variant: KButtonVariant.secondary,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ],
      onClose: () => Navigator.of(ctx).pop(false),
    ),
  );
  if (open != true) return false;
  return ExactAlarmPermission.request();
}
