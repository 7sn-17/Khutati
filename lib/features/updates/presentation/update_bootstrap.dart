import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/update_controller.dart';

/// Runs a silent, throttled update check after the first frame and whenever the
/// app returns to the foreground. It never blocks the widget tree and never
/// shows a dialog on its own.
class UpdateBootstrap extends ConsumerStatefulWidget {
  const UpdateBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UpdateBootstrap> createState() => _UpdateBootstrapState();
}

class _UpdateBootstrapState extends ConsumerState<UpdateBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        unawaited(
          ref.read(updateControllerProvider.notifier).maybeCheck(),
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(updateControllerProvider.notifier).maybeCheck());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
