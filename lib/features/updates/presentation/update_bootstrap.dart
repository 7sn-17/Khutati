import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../application/update_controller.dart';
import 'update_dialog.dart';

/// Runs a silent, throttled update check after the first frame and whenever the
/// app returns to the foreground. It never blocks the widget tree; when the
/// check finds a newer release it presents the branded update dialog.
class UpdateBootstrap extends ConsumerStatefulWidget {
  const UpdateBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UpdateBootstrap> createState() => _UpdateBootstrapState();
}

class _UpdateBootstrapState extends ConsumerState<UpdateBootstrap>
    with WidgetsBindingObserver {
  bool _dialogOpen = false;
  int? _presentedVersionCode;
  int _lastRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        unawaited(ref.read(updateControllerProvider.notifier).maybeCheck());
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

  Future<void> _present(UpdateState state) async {
    // A silent release is presented once per version. A manual Settings check
    // bumps `requestId`, which is allowed to re-open the same release.
    final bool manual = state.requestId != _lastRequestId;
    if (_dialogOpen ||
        state.manifest == null ||
        (!manual && _presentedVersionCode == state.manifest!.versionCode)) {
      return;
    }
    _lastRequestId = state.requestId;
    _dialogOpen = true;
    _presentedVersionCode = state.manifest!.versionCode;
    try {
      // Wait briefly for a valid navigator context so the modal never fails
      // silently when the check resolves very early.
      BuildContext? context = rootNavigatorKey.currentContext;
      for (int i = 0; i < 20 && (context == null || !context.mounted); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        context = rootNavigatorKey.currentContext;
      }
      if (context != null && context.mounted) {
        await showUpdateDialog(
          context,
          manifest: state.manifest!,
          source: state.source,
        );
      }
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updateControllerProvider, (
      UpdateState? previous,
      UpdateState next,
    ) {
      if (next.hasUpdate) {
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          if (mounted) unawaited(_present(next));
        });
      }
    });
    return widget.child;
  }
}
