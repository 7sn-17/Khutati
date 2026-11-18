import 'package:flutter/material.dart';

/// Native press feedback: the child scales down smoothly while a pointer is
/// held, then springs back with a gentle overshoot.
///
/// Uses [Listener] rather than a gesture recognizer so it never competes with
/// the `InkWell`/`GestureDetector` that actually handles the tap.
class PressScale extends StatefulWidget {
  const PressScale({
    required this.child,
    this.scale = 0.97,
    this.duration = const Duration(milliseconds: 120),
    this.releaseDuration = const Duration(milliseconds: 120),
    this.pressCurve = Curves.easeOut,
    this.releaseCurve = Curves.easeOut,
    this.onPressed,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final double scale;

  /// Duration of the press-down shrink.
  final Duration duration;

  /// Duration of the release spring.
  final Duration releaseDuration;

  final Curve pressCurve;
  final Curve releaseCurve;

  /// Fired on pointer-down, before the tap completes. Useful for haptics.
  final VoidCallback? onPressed;

  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleDown(PointerDownEvent _) {
    if (!widget.enabled) return;
    _set(true);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool active = _pressed && widget.enabled && !reduce;

    return Listener(
      onPointerDown: _handleDown,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: active ? widget.duration : widget.releaseDuration,
        curve: active ? widget.pressCurve : widget.releaseCurve,
        child: widget.child,
      ),
    );
  }
}
