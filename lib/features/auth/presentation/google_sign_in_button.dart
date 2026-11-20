import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/feedback.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../application/auth_providers.dart';
import '../data/supabase_auth.dart';

/// Official four-colour Google mark, path-for-path from the login reference.
const String googleLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.5 5.4 2.6 13.2l7.9 6.1C12.4 13.6 17.7 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 3-2.3 5.5-4.8 7.2l7.5 5.8c4.4-4.1 7.1-10.1 7.1-17.5z"/>
  <path fill="#FBBC05" d="M10.5 28.7a14.5 14.5 0 0 1 0-9.4l-7.9-6.1a24 24 0 0 0 0 21.6l7.9-6.1z"/>
  <path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.5-5.8c-2.1 1.4-4.8 2.3-8.4 2.3-6.3 0-11.6-4.1-13.5-9.8l-7.9 6.1C6.5 42.6 14.6 48 24 48z"/>
</svg>
''';

/// The one Google sign-in control used by both Login and Settings.
///
/// Colours are injectable so Login can mirror the HTML variables exactly while
/// Settings uses the app palette. The flow and error handling stay identical.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({
    this.label = 'المتابعة باستخدام Google',
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.height = 62,
    this.showShadow = false,
    super.key,
  });

  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double height;
  final bool showShadow;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider).signInWithGoogle();
    } on AuthFailure catch (error) {
      if (mounted) {
        showKToast(context, error.message, kind: KToastKind.error);
      }
    } catch (_) {
      if (mounted) {
        showKToast(
          context,
          'تعذّر تسجيل الدخول. تحقق من الإنترنت وحاول مرة أخرى.',
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
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Color background = widget.backgroundColor ?? palette.tx;
    final Color foreground = widget.foregroundColor ?? palette.bg;
    final Color border = widget.borderColor ?? background;

    return Semantics(
      button: true,
      label: widget.label,
      child: PressScale(
        scale: 0.95,
        duration: const Duration(milliseconds: 100),
        releaseDuration: const Duration(milliseconds: 280),
        pressCurve: Curves.easeOutCubic,
        releaseCurve: Curves.easeOutBack,
        enabled: !_busy,
        onPressed: () => ref.read(hapticsProvider).light(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _busy ? null : _signIn,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedOpacity(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              opacity: _busy ? 0.72 : 1,
              child: Container(
                height: widget.height,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: border),
                  boxShadow: widget.showShadow && !reduceMotion
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (_busy)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(foreground),
                        ),
                      )
                    else
                      SvgPicture.string(googleLogoSvg, width: 22, height: 22),
                    const SizedBox(width: 10),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
