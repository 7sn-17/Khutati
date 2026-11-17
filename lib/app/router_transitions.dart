import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design/tokens.dart';

/// Shared page transition: a short fade with a 2% rise, matching the motion
/// language of the prototype's card entrances. Native and cheap — no hero
/// flights needed for a full-screen push.
CustomTransitionPage<void> khutatiPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Duration(milliseconds: KMotion.cardEntranceMs),
    reverseTransitionDuration: Duration(milliseconds: KMotion.navMs),
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
