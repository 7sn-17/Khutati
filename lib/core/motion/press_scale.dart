import 'package:flutter/material.dart';

/// Native press feedback: the child scales down slightly while a pointer is
/// held, then springs back.
///
/// Uses [Listener] rather than a gesture recognizer so it never competes with
/// the `InkWell`/`GestureDetector` that actually handles the tap.
class PressScale extends StatefulWidget {
  const PressScale({
    required this.child,
    this.scale = 0.97,
    this.duration = const Duration(milliseconds: 120),
    super.key,
  });

  final Widget child;
  final double scale;
  final Duration duration;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !reduce ? widget.scale : 1,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
