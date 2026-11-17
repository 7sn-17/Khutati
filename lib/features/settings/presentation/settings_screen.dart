import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/settings/notification_prefs.dart';
import '../../../core/settings/theme_mode_controller.dart';
import '../../../l10n/l10n.dart';
import '../../updates/application/update_controller.dart';
import '../../updates/domain/app_release.dart';

/// Settings — the fifth tab (PRD 5.11).
///
/// Phase 3.1 builds the shell: appearance, haptics and notification
/// preferences are live and persisted. Backup/restore and account land in
/// Phase 5 and are shown here as disabled rows with a "coming soon" marker so
/// the information architecture is already final.
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
    final bool hapticsEnabled = ref.watch(hapticsEnabledProvider);
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
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
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
              _ToggleRow(
                title: l10n.settingsHaptics,
                value: hapticsEnabled,
                onChanged: (bool value) {
                  ref.read(hapticsProvider).selection();
                  ref.read(hapticsEnabledProvider.notifier).set(value);
                },
              ),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsNotifications),
        _SettingsCard(
          child: Column(
            children: <Widget>[
              _ToggleRow(
                title: l10n.settingsNotifTasks,
                value: prefs.tasks,
                onChanged: ref.read(notificationPrefsProvider.notifier).setTasks,
              ),
              _ToggleRow(
                title: l10n.settingsNotifDaily,
                value: prefs.daily,
                onChanged: ref.read(notificationPrefsProvider.notifier).setDaily,
              ),
              _ToggleRow(
                title: l10n.settingsNotifReview,
                value: prefs.review,
                onChanged: ref.read(notificationPrefsProvider.notifier).setReview,
              ),
              _ToggleRow(
                title: l10n.settingsNotifTimer,
                value: prefs.timer,
                onChanged: ref.read(notificationPrefsProvider.notifier).setTimer,
              ),
              const SizedBox(height: 6),
              _Hint(text: l10n.settingsNotificationsHint),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsData),
        _SettingsCard(
          child: Column(
            children: <Widget>[
              _ActionRow(
                title: l10n.settingsBackupExport,
                icon: Icons.upload_file_outlined,
                badge: l10n.settingsComingSoon,
              ),
              _ActionRow(
                title: l10n.settingsBackupImport,
                icon: Icons.download_outlined,
                badge: l10n.settingsComingSoon,
              ),
              const SizedBox(height: 6),
              _Hint(text: l10n.settingsBackupHint),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsAccount),
        _SettingsCard(
          child: Column(
            children: <Widget>[
              _ActionRow(
                title: l10n.settingsSignIn,
                icon: Icons.login,
                badge: l10n.settingsComingSoon,
              ),
              const SizedBox(height: 6),
              _Hint(text: l10n.settingsAccountHint),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsUpdates),
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ActionRow(
                title: l10n.settingsInstalledVersion,
                icon: Icons.phone_android,
                trailing: Text(
                  AppInfo.versionLabel,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.muteSize,
                    fontWeight: FontWeight.w500,
                    color: palette.gold,
                  ),
                ),
              ),
              const _UpdatePanel(),
            ],
          ),
        ),
        KSectionHeader(title: l10n.settingsAbout),
        _SettingsCard(
          child: _ActionRow(
            title: l10n.appName,
            icon: Icons.info_outline,
            trailing: Text(
              AppInfo.versionLabel,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.muteSize,
                color: palette.mute,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UpdatePanel extends ConsumerWidget {
  const _UpdatePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final UpdateState state = ref.watch(updateControllerProvider);
    final UpdateManifest? manifest = state.manifest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (state.isChecking)
          _StatusLine(
            text: l10n.updateChecking,
            spinner: true,
          )
        else if (state.hasUpdate && manifest != null)
          _AvailableUpdate(manifest: manifest, source: state.source)
        else if (state.status == UpdateStatus.failed)
          _StatusLine(
            icon: Icons.cloud_off_outlined,
            text: l10n.updateFailed,
            color: palette.mute,
          )
        else if (state.status == UpdateStatus.upToDate)
          _StatusLine(
            icon: Icons.check_circle_outline,
            text: l10n.updateUpToDate,
            color: palette.ok,
          )
        else
          _StatusLine(
            icon: Icons.wifi_tethering,
            text: l10n.updateHint,
            color: palette.mute,
          ),
        const SizedBox(height: 10),
        KButton(
          label: l10n.updateCheck,
          variant: KButtonVariant.secondary,
          expand: true,
          onPressed: state.isChecking
              ? null
              : () {
                  unawaited(
                    ref
                        .read(updateControllerProvider.notifier)
                        .check(force: true),
                  );
                },
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    this.icon,
    this.color,
    this.spinner = false,
  });

  final String text;
  final IconData? icon;
  final Color? color;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: <Widget>[
          if (spinner)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.ok,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 17, color: color ?? palette.mute),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.smallSize,
                color: color ?? palette.mute,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableUpdate extends ConsumerWidget {
  const _AvailableUpdate({required this.manifest, this.source});

  final UpdateManifest manifest;
  final UpdateSource? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final String? notes = manifest.notes?.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
        border: Border.all(color: palette.gold.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.system_update_alt, size: 18, color: palette.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.updateAvailable(manifest.versionName),
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.quoteSize,
                    fontWeight: FontWeight.w500,
                    color: palette.tx,
                  ),
                ),
              ),
            ],
          ),
          if (source != null) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(KMetrics.pillRadius),
                border: Border.all(color: palette.line),
              ),
              child: Text(
                source == UpdateSource.supabase
                    ? l10n.updateSourceSupabase
                    : l10n.updateSourceGithub,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.tagSize,
                  color: palette.mute,
                ),
              ),
            ),
          ],
          if (notes != null && notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              l10n.updateNotes,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.smallSize,
                fontWeight: FontWeight.w500,
                color: palette.tx,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              notes,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.smallSize,
                color: palette.mute,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: KButton(
                  label: l10n.updateNow,
                  expand: true,
                  onPressed: () => unawaited(_open(context, ref)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KButton(
                  label: l10n.updateSkip,
                  variant: KButtonVariant.secondary,
                  expand: true,
                  onPressed: () => unawaited(
                    ref.read(updateControllerProvider.notifier).skip(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final bool opened = await ref
        .read(updateControllerProvider.notifier)
        .openDownload(manifest);
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.updateLaunchFailed)),
      );
    }
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
              constraints: const BoxConstraints(minHeight: KMetrics.buttonMinHeight),
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
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
            onChanged: onChanged,
            activeColor: palette.ok,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.icon,
    this.badge,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return ConstrainedBox(
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
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.card2,
                borderRadius: BorderRadius.circular(KMetrics.pillRadius),
                border: Border.all(color: palette.line),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.tagSize,
                  color: palette.mute,
                ),
              ),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: KTypography.smallSize,
          color: palette.mute,
          height: 1.5,
        ),
      ),
    );
  }
}
