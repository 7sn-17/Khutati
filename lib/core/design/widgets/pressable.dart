import 'package:flutter/material.dart';

import '../../motion/press_scale.dart';
import '../../sound/sound_effects.dart';

/// The visual half of a pressable surface: a `Material` that carries the fill
/// and the ripple, with the tap area filling the whole rounded rect.
///
/// Put it *inside* a decorated container when the background animates (chips,
/// cards, nav items) so the splash paints above that background. Use
/// [KPressable] instead when the surface owns its own colour.
class KInkSurface extends StatelessWidget {
  const KInkSurface({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = BorderRadius.zero,
    this.shape,
    this.color,
    this.border,
    this.padding = EdgeInsets.zero,
    this.minHeight,
    this.expand = false,
    this.sound = KSound.tap,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  /// Overrides [borderRadius] for non-rectangular surfaces (the circular focus
  /// controls). Supply the outline's own `side` on the shape in that case.
  final ShapeBorder? shape;

  /// Fill colour. `null` keeps the Material transparent so a parent decoration
  /// shows through while the ripple still paints on top of it.
  final Color? color;
  final BorderSide? border;
  final EdgeInsetsGeometry padding;
  final double? minHeight;
  final bool expand;

  /// Played on a completed tap, never on press-down.
  final KSound sound;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool active = enabled && onTap != null;
    Widget content = Padding(padding: padding, child: child);
    if (minHeight != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight!),
        child: content,
      );
    }
    if (expand) {
      content = SizedBox(width: double.infinity, child: content);
    }

    return RepaintBoundary(
      child: Material(
        color: color ?? Colors.transparent,
        shape:
            shape ??
            RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: border ?? BorderSide.none,
            ),
        // The ripple must be clipped to the same radius as the fill.
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active
              ? () {
                  SoundEffects.play(sound);
                  onTap!();
                }
              : null,
          onLongPress: active ? onLongPress : null,
          borderRadius: borderRadius,
          child: content,
        ),
      ),
    );
  }
}

/// A complete tactile surface: squish on press, clipped ripple, one sound on
/// tap, and a repaint boundary so the animation never dirties the page.
class KPressable extends StatelessWidget {
  const KPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = BorderRadius.zero,
    this.color,
    this.border,
    this.padding = EdgeInsets.zero,
    this.minHeight,
    this.expand = false,
    this.sound = KSound.tap,
    this.enabled = true,
    this.scale = 0.96,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final Color? color;
  final BorderSide? border;
  final EdgeInsetsGeometry padding;
  final double? minHeight;
  final bool expand;
  final KSound sound;
  final bool enabled;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final bool active = enabled && onTap != null;
    return Semantics(
      button: true,
      enabled: active,
      child: PressScale(
        scale: scale,
        enabled: active,
        duration: const Duration(milliseconds: 100),
        releaseDuration: const Duration(milliseconds: 140),
        child: KInkSurface(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          color: color,
          border: border,
          padding: padding,
          minHeight: minHeight,
          expand: expand,
          sound: sound,
          enabled: enabled,
          child: child,
        ),
      ),
    );
  }
}
