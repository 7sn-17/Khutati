import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/alarm_settings.dart';
import '../../../core/device/battery_optimization.dart';
import '../../../core/device/exact_alarm_prompt.dart';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_info.dart';
import '../../../core/design/khutati_icons.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/feedback.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/settings/notification_prefs.dart';
import '../../../core/settings/theme_mode_controller.dart';
import '../../../core/sound/sound_effects.dart';
import '../../../l10n/l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/account_section.dart';
import '../../updates/application/update_controller.dart';
import '../../updates/domain/app_release.dart';
import '../../updates/presentation/update_dialog.dart';

/// Settings — the fifth tab (PRD 5.11).
///
/// Appearance, sound effects, notifications, account and updates are live and
/// persisted. There are no placeholder toggles: every row changes real app
/// behaviour.
///
/// Updates are live: a silent check runs at launch, and this panel is where the
/// user can check on demand, read release notes and start the APK download.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final bool soundEnabled = ref.watch(soundEffectsEnabledProvider);
    final bool signedIn = ref.watch(isSignedInProvider);
    final NotificationPrefs prefs = ref.watch(notificationPrefsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KMetrics.appPaddingX,
        KMetrics.appPaddingTop,
        KMetrics.appPaddingX,
        KMetrics.appPaddingBottom,
      ),
      children: <Widget>[
        Text(
          l10n.settingsTitle,
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: KTypography.heroTitleSize,
            fontWeight: FontWeight.w700,
            height: KTypography.heroTitleHeight,
            color: palette.tx,
          ),
        ),
        KSectionHeader(title: 'الحساب'),
        const AccountSection(),
        KSectionHeader(title: l10n.settingsAppearance),
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ThemeSelector(
                mode: themeMode,
                onChanged: (ThemeMode mode) {
                  ref.read(hapticsProvider).selection();
                  ref.read(themeModeProvider.notifier).set(mode);
                },
              ),
              const SizedBox(height: 12),
              _SettingsSwitchRow(
                title: 'المؤثرات الصوتية',
                value: soundEnabled,
                onChanged: ref.read(soundEffectsEnabledProvider.notifier).set,
              ),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsPlanSection),
        _SettingsNavRow(
          icon: Icons.event_available_rounded,
          title: l10n.settingsPracticalDays,
          subtitle: l10n.settingsPracticalDaysSubtitle,
          onTap: () => context.push('/settings/practical-days'),
        ),
        KSectionHeader(title: l10n.settingsNotifications),
        _SettingsCard(
          child: Column(
            children: <Widget>[
              _SettingsSwitchRow(
                title: l10n.settingsNotifTasks,
                value: prefs.tasks,
                onChanged: (bool value) async {
                  await ref
                      .read(notificationPrefsProvider.notifier)
                      .setTasks(value);
                  // Turning reminders on is an explicit request for scheduled
                  // alerts; without exact alarms they arrive late or not at all.
                  if (value && context.mounted) {
                    await maybePromptExactAlarms(context, force: true);
                  }
                },
              ),
              _SettingsSwitchRow(
                title: l10n.settingsNotifDaily,
                value: prefs.daily,
                onChanged: ref
                    .read(notificationPrefsProvider.notifier)
                    .setDaily,
              ),
              _SettingsSwitchRow(
                title: l10n.settingsNotifReview,
                value: prefs.review,
                onChanged: ref
                    .read(notificationPrefsProvider.notifier)
                    .setReview,
              ),
              _SettingsSwitchRow(
                title: l10n.settingsNotifTimer,
                value: prefs.timer,
                onChanged: (bool value) async {
                  await ref
                      .read(notificationPrefsProvider.notifier)
                      .setTimer(value);
                  // The session alert is the one that must be exact.
                  if (value && context.mounted) {
                    await maybePromptExactAlarms(context, force: true);
                  }
                },
              ),
              const SizedBox(height: 6),
              const _AlarmStatusRow(),
              const SizedBox(height: 6),
              const _BatteryStatusRow(),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsUpdates),
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      size: 20,
                      color: palette.gold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.settingsInstalledVersion,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: KTypography.bodySize,
                            fontWeight: FontWeight.w500,
                            color: palette.tx,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(KMetrics.pillRadius),
                      border: Border.all(
                        color: palette.gold.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      AppInfo.versionName,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                        fontWeight: FontWeight.w600,
                        color: palette.gold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: palette.line),
              const SizedBox(height: 12),
              const _UpdatePanel(),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsAbout),
        _SettingsCard(
          child: Column(
            children: <Widget>[
              _SettingsActionRow(
                title: l10n.settingsAbout,
                icon: Icons.info_outline,
                trailing: Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: palette.mute,
                ),
                onTap: () => _openAbout(context),
              ),
              Divider(height: 1, color: palette.line),
              _SettingsActionRow(
                title: l10n.settingsDeveloper,
                icon: Icons.code_rounded,
                trailing: Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: palette.mute,
                ),
                onTap: () => _openDeveloper(context),
              ),
              Divider(height: 1, color: palette.line),
              _SettingsActionRow(
                title: l10n.settingsShare,
                icon: Icons.share_rounded,
                trailing: Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: palette.mute,
                ),
                onTap: () => _shareApp(context),
              ),
            ],
          ),
        ),
        if (signedIn) ...<Widget>[
          const SizedBox(height: 24),
          const SignOutButton(),
        ],
      ],
    );
  }

  void _openAbout(BuildContext context) {
    showKDialog<void>(
      context: context,
      builder: (_) => const _AboutModalContent(),
    );
  }

  void _openDeveloper(BuildContext context) {
    showKDialog<void>(
      context: context,
      builder: (_) => const _DeveloperModalContent(),
    );
  }

  /// Hands the pre-formatted invitation to the system share sheet.
  ///
  /// The text lives in the ARB, so the message is translated with the rest of
  /// the UI and the direct-download URL is never assembled in two places.
  Future<void> _shareApp(BuildContext context) async {
    final String message = context.l10n.settingsShareMessage;
    final String subject = context.l10n.settingsShare;
    try {
      await Share.share(message, subject: subject);
    } catch (_) {
      // A device with no share target at all is rare, but a silent no-op is
      // worse than saying so.
      if (!context.mounted) return;
      showKToast(context, 'تعذّر فتح نافذة المشاركة.', kind: KToastKind.error);
    }
  }
}

class _UpdatePanel extends ConsumerWidget {
  const _UpdatePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final UpdateState state = ref.watch(updateControllerProvider);
    final UpdateManifest? manifest = state.manifest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 10),
        KButton(
          label: l10n.updateCheck,
          variant: KButtonVariant.secondary,
          expand: true,
          loading: state.isChecking,
          onPressed: state.isChecking
              ? null
              : () async {
                  // The app-level presenter owns the update modal. Asking the
                  // controller here would open a second copy behind it.
                  await ref
                      .read(updateControllerProvider.notifier)
                      .check(force: true);
                  if (!context.mounted) return;
                  final UpdateState next = ref.read(updateControllerProvider);
                  if (next.status == UpdateStatus.upToDate) {
                    showKToast(
                      context,
                      l10n.updateUpToDate,
                      kind: KToastKind.success,
                    );
                  } else if (next.status == UpdateStatus.failed) {
                    // The check did not happen. Saying "up to date" here would
                    // be a lie the user cannot detect.
                    showKToast(
                      context,
                      l10n.updateFailed,
                      kind: KToastKind.error,
                    );
                  }
                },
        ),
        if (manifest != null) ...<Widget>[
          const SizedBox(height: 10),
          KButton(
            label: l10n.updateView,
            expand: true,
            onPressed: () => unawaited(
              showUpdateDialog(
                context,
                manifest: manifest,
                source: state.source,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AboutModalContent extends ConsumerWidget {
  const _AboutModalContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Header: official app mark + name + close. No redundant "About" title.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Row(
            children: <Widget>[
              // Official launcher icon asset.
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.appName,
                      style: TextStyle(
                        fontFamily: KTypography.displayFamily,
                        fontSize: KTypography.h2Size,
                        fontWeight: FontWeight.w700,
                        color: palette.tx,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'v${AppInfo.versionName}',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.card2,
                  ),
                  child: Icon(Icons.close, size: 20, color: palette.mute),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          child: Text(
            l10n.aboutAppBody,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.bodySize,
              height: 1.6,
              color: palette.tx,
            ),
          ),
        ),
        const SizedBox(height: 18),
        KButton(
          label: 'إغلاق',
          variant: KButtonVariant.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _DeveloperModalContent extends ConsumerWidget {
  const _DeveloperModalContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  l10n.settingsDeveloper,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: KTypography.h2Size,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.card2,
                  ),
                  child: Icon(Icons.close, size: 20, color: palette.mute),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.card2,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 18,
                  color: palette.mute,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.aboutDeveloperName,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.bodySize,
                    fontWeight: FontWeight.w600,
                    color: palette.tx,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'تواصل معنا / أرسل ملاحظاتك',
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.smallSize,
                color: palette.mute,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            children: <Widget>[
              _DeveloperActionTile(
                glyph: KhutatiBrandIcons.telegramPath,
                brand: KhutatiBrandIcons.telegram,
                label: l10n.aboutTelegram,
                handle: '@DOVx3',
                url: 'https://t.me/DOVx3',
              ),
              const SizedBox(height: 10),
              _DeveloperActionTile(
                glyph: KhutatiBrandIcons.whatsappPath,
                brand: KhutatiBrandIcons.whatsapp,
                label: l10n.aboutWhatsapp,
                handle: '+963 984 623 461',
                url: 'https://wa.me/963984623461',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        KButton(
          label: 'إغلاق',
          variant: KButtonVariant.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// One contact row: the official brand mark, a label, the handle and an
/// affordance that it opens outside the app.
class _DeveloperActionTile extends ConsumerWidget {
  const _DeveloperActionTile({
    required this.glyph,
    required this.brand,
    required this.label,
    required this.handle,
    required this.url,
  });

  final String glyph;
  final Color brand;
  final String label;
  final String handle;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KhutatiPalette palette = context.palette;

    return Semantics(
      button: true,
      label: '$label، $handle',
      child: PressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(url),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.card2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.line),
              ),
              child: Row(
                children: <Widget>[
                  KBrandMark(path: glyph, color: brand, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: KTypography.bodySize,
                            fontWeight: FontWeight.w500,
                            color: palette.tx,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          handle,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: KTypography.muteSize,
                            color: palette.mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: palette.mute,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(String target) async {
    final Uri uri = Uri.parse(target);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A device without the app or a browser simply keeps the sheet open.
    }
  }
}

/// A compact navigation row inside a settings section.
///
/// Settings stays a list of one-line decisions; anything that needs its own
/// layout opens a dedicated screen instead of growing a card here.
class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Semantics(
      button: true,
      label: title,
      child: KCard(
        showPattern: false,
        padding: const EdgeInsets.symmetric(
          horizontal: KMetrics.statPaddingX,
          vertical: KMetrics.statPaddingY,
        ),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: palette.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: KTypography.quoteSize,
                      fontWeight: FontWeight.w600,
                      color: palette.tx,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: KTypography.tagSize,
                      height: 1.5,
                      color: palette.mute,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_left_rounded, size: 20, color: palette.mute),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KCard(
      showPattern: false,
      padding: const EdgeInsets.symmetric(
        horizontal: KMetrics.statPaddingX,
        vertical: KMetrics.statPaddingY,
      ),
      child: child,
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Row(
      children: <Widget>[
        _ThemeOption(
          label: l10n.settingsThemeAuto,
          selected: mode == ThemeMode.system,
          onTap: () => onChanged(ThemeMode.system),
        ),
        const SizedBox(width: 8),
        _ThemeOption(
          label: l10n.settingsThemeDark,
          selected: mode == ThemeMode.dark,
          onTap: () => onChanged(ThemeMode.dark),
        ),
        const SizedBox(width: 8),
        _ThemeOption(
          label: l10n.settingsThemeLight,
          selected: mode == ThemeMode.light,
          onTap: () => onChanged(ThemeMode.light),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: PressScale(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
            child: AnimatedContainer(
              duration: Duration(milliseconds: KMotion.navMs),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(
                minHeight: KMetrics.buttonMinHeight,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.tx : Colors.transparent,
                borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
                border: Border.all(color: selected ? palette.tx : palette.line),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.muteSize,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? palette.bg : palette.mute,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KMetrics.tapTarget),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.quoteSize,
                color: palette.tx,
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: palette.ok,
            // Played after the change so the mute switch itself stays silent
            // when it turns sound off, and ticks when it turns sound back on.
            onChanged: (bool next) {
              onChanged(next);
              SoundEffects.toggle();
            },
          ),
        ],
      ),
    );
  }
}

/// The shared look for a permission row: icon, title, live state, chevron.
///
/// The alarm row and the battery row both use it, so the two are identical by
/// construction — same height, same colours, same tap target.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.granted,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;

  /// `true` = allowed, `false` = denied. Ignored while [loading].
  final bool granted;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    final Widget status;
    if (loading) {
      status = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: palette.mute),
      );
    } else {
      final Color color = granted ? palette.ok : palette.red;
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            granted ? 'مفعل' : 'غير مفعل',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      child: KInkSurface(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: KMetrics.tapTarget),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 20, color: palette.mute),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.quoteSize,
                    color: palette.tx,
                  ),
                ),
              ),
              status,
              const SizedBox(width: 6),
              Icon(Icons.chevron_left_rounded, size: 20, color: palette.mute),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two grants a reminder needs, with their live state.
///
/// Read on mount and re-read on every resume, because both are granted in
/// system settings and neither reaches Dart on its own. Tapping sends the user
/// straight to whichever grant is missing.
class _AlarmStatusRow extends StatefulWidget {
  const _AlarmStatusRow();

  @override
  State<_AlarmStatusRow> createState() => _AlarmStatusRowState();
}

class _AlarmStatusRowState extends State<_AlarmStatusRow>
    with WidgetsBindingObserver {
  AlarmPermissions? _permissions;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final AlarmPermissions next = await AlarmSettings.read();
    if (!mounted) return;
    setState(() => _permissions = next);
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool opened = await AlarmSettings.openMissing(
      _permissions ?? const AlarmPermissions.unknown(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) {
      showKToast(context, 'تعذّر فتح إعدادات النظام.', kind: KToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PermissionRow(
      icon: Icons.alarm_rounded,
      title: 'المنبهات والمذكرات',
      granted: _permissions?.allGranted ?? false,
      loading: _permissions == null,
      onTap: _open,
    );
  }
}

/// Battery-optimisation exemption, in the same shape as the alarm row.
///
/// The exemption is what keeps the focus service alive through Doze, so the row
/// reads it live and deep-links to the system sheet. Some OEM skins block
/// `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; the native side then falls
/// back to the battery list and finally to app details, and only reports
/// failure when every option was refused.
class _BatteryStatusRow extends StatefulWidget {
  const _BatteryStatusRow();

  @override
  State<_BatteryStatusRow> createState() => _BatteryStatusRowState();
}

class _BatteryStatusRowState extends State<_BatteryStatusRow>
    with WidgetsBindingObserver {
  bool? _unrestricted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final bool next = await BatteryOptimization.isUnrestricted();
    if (!mounted) return;
    setState(() => _unrestricted = next);
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool opened = await BatteryOptimization.requestUnrestricted();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) {
      showKToast(
        context,
        'تعذّر فتح إعدادات البطارية.',
        kind: KToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PermissionRow(
      icon: Icons.battery_saver_rounded,
      title: 'تحسين استخدام البطارية',
      granted: _unrestricted ?? false,
      loading: _unrestricted == null,
      onTap: _open,
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.title,
    required this.icon,
    this.trailing,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    final Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KMetrics.tapTarget),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: palette.mute),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.quoteSize,
                color: palette.tx,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: content,
        ),
      ),
    );
  }
}
