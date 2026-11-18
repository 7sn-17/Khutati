import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/widgets/controls.dart';
import '../design/widgets/dialogs.dart';
import 'exact_alarm_permission.dart';

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
