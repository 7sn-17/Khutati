import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/feedback.dart';
import '../../../core/design/widgets/surfaces.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../application/auth_providers.dart';
import '../data/supabase_auth.dart';
import 'google_sign_in_button.dart';

/// Account block at the very top of Settings.
///
/// Signed-in: the Google identity (avatar, name, email) plus a pencil that
/// writes the new name to Supabase Auth metadata.
/// Signed-out: a value-first card and the same Google button used on Login.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? user = ref.watch(currentUserProvider);
    return user == null ? const _SignedOutCard() : _SignedInCard(user: user);
  }
}

class _SignedInCard extends ConsumerWidget {
  const _SignedInCard({required this.user});

  final User user;

  String get _name {
    final Map<String, dynamic>? meta = user.userMetadata;
    final Object? raw = meta?['full_name'] ?? meta?['name'];
    final String value = raw?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
    final String email = user.email ?? '';
    return email.contains('@') ? email.split('@').first : 'مستخدم خطتي';
  }

  String? get _avatar {
    final Map<String, dynamic>? meta = user.userMetadata;
    final Object? raw =
        meta?['avatar_url'] ?? meta?['picture'] ?? meta?['avatar'];
    final String value = raw?.toString() ?? '';
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KhutatiPalette palette = context.palette;
    final String name = _name;
    final String email = user.email ?? '—';

    return KCard(
      showPattern: true,
      borderColor: palette.gold.withValues(alpha: 0.22),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          _Avatar(url: _avatar, name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.tx,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 13,
                    color: palette.mute,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.ok,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'متزامن مع حسابك',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 11,
                        color: palette.ok,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'تعديل الاسم',
            child: Semantics(
              button: true,
              label: 'تعديل الاسم',
              child: PressScale(
                child: Material(
                  color: palette.card2,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _editName(context, ref, name),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: palette.tx,
                      ),
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

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    ref.read(hapticsProvider).selection();
    final String? next = await showKDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _EditNameDialog(initial: current),
    );
    if (next == null || next == current || !context.mounted) return;
    showKToast(context, 'تم تحديث اسمك.', kind: KToastKind.success);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final String trimmed = name.trim();
    final String initial = trimmed.isEmpty
        ? 'خ'
        : String.fromCharCode(trimmed.runes.first);

    final Widget fallback = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      color: palette.card2,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: KTypography.displayFamily,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: palette.tx,
        ),
      ),
    );

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.line),
      ),
      child: ClipOval(
        child: url == null
            ? fallback
            : Image.network(
                url!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Offline-first: the initials are the default, not a blank
                // circle. A slow or failed Google fetch never blocks Settings.
                loadingBuilder: (
                  BuildContext context,
                  Widget child,
                  ImageChunkEvent? progress,
                ) => progress == null ? child : fallback,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stack,
                ) => fallback,
              ),
      ),
    );
  }
}

class _EditNameDialog extends ConsumerStatefulWidget {
  const _EditNameDialog({required this.initial});

  final String initial;

  @override
  ConsumerState<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends ConsumerState<_EditNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'لا يمكن ترك الاسم فارغاً.');
      return;
    }
    if (value.length > 60) {
      setState(() => _error = 'الاسم طويل جداً.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider).updateDisplayName(value);
      if (mounted) Navigator.of(context).pop(value);
    } on AuthFailure catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'تعذّر تحديث الاسم. تحقق من الإنترنت وحاول مرة أخرى.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return KDialog(
      eyebrow: 'حسابك',
      title: 'تعديل الاسم',
      icon: Icons.edit_rounded,
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      child: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        style: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: 16,
          color: palette.tx,
        ),
        decoration: InputDecoration(
          hintText: 'اسمك',
          errorText: _error,
          counterText: '',
          filled: true,
          fillColor: palette.card2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.gold, width: 1.5),
          ),
        ),
      ),
      actions: <KDialogAction>[
        KDialogAction(
          label: 'حفظ',
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
        KDialogAction(
          label: 'إلغاء',
          variant: KButtonVariant.secondary,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _SignedOutCard extends StatelessWidget {
  const _SignedOutCard();

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return KCard(
      showPattern: true,
      borderColor: palette.gold.withValues(alpha: 0.24),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.gold.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.gold.withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  'زائر',
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: palette.gold,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'أنت الآن زائر',
                      style: TextStyle(
                        fontFamily: KTypography.displayFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: palette.tx,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'تقدمك محفوظ على هذا الجهاز',
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 13,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'يمكنك الدراسة الآن دون حساب. سجّل الدخول بحساب Google لتبقى خطتك '
            'وإنجازاتك وسجل تركيزك معك إذا غيّرت هاتفك أو أعدت تثبيت التطبيق.',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 14,
              height: 1.75,
              color: palette.mute,
            ),
          ),
          const SizedBox(height: 16),
          GoogleSignInButton(
            height: 56,
            backgroundColor: dark ? palette.card : palette.tx,
            foregroundColor: dark ? palette.tx : palette.bg,
            borderColor: dark ? palette.line : palette.tx,
          ),
        ],
      ),
    );
  }
}

/// Destructive but reversible action, pinned to the very bottom of Settings.
class SignOutButton extends ConsumerStatefulWidget {
  const SignOutButton({super.key});

  @override
  ConsumerState<SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends ConsumerState<SignOutButton> {
  bool _busy = false;

  Future<void> _confirm() async {
    ref.read(hapticsProvider).selection();
    final bool? confirmed = await showKDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final KhutatiPalette palette = ctx.palette;
        return KDialog(
          eyebrow: 'الحساب',
          title: 'تسجيل الخروج',
          icon: Icons.logout_rounded,
          accent: palette.red,
          message:
              'سيتم تسجيل خروجك من هذا الجهاز. ستحتاج إلى اتصال بالإنترنت '
              'لتسجيل الدخول مرة أخرى، لكن تقدمك المحلي يبقى محفوظاً.',
          onClose: () => Navigator.of(ctx).pop(false),
          actions: <KDialogAction>[
            KDialogAction(
              label: 'تسجيل الخروج',
              icon: Icons.logout_rounded,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            KDialogAction(
              label: 'إلغاء',
              variant: KButtonVariant.secondary,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider).signOut();
      // The router observes the auth stream and replaces the whole shell with
      // /login; no manual navigation is needed (and the stack is cleared).
    } on AuthFailure catch (error) {
      if (mounted) {
        showKToast(context, error.message, kind: KToastKind.error);
      }
    } catch (_) {
      if (mounted) {
        showKToast(
          context,
          'تعذّر تسجيل الخروج. تحقق من الإنترنت وحاول مرة أخرى.',
          kind: KToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Semantics(
      button: true,
      label: 'تسجيل الخروج',
      child: PressScale(
        scale: 0.98,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _busy ? null : _confirm,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.red.withValues(alpha: 0.40)),
              ),
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(palette.red),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.logout_rounded,
                          size: 20,
                          color: palette.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'تسجيل الخروج',
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: palette.red,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
