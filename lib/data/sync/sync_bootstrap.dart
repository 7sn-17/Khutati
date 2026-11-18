import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_sync_service.dart';

/// Starts the five-minute sync clock and flushes on the two moments Android
/// gives us for free: app start and app pause. Never blocks the widget tree.
class SyncBootstrap extends ConsumerStatefulWidget {
  const SyncBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncBootstrap> createState() => _SyncBootstrapState();
}

class _SyncBootstrapState extends ConsumerState<SyncBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Touch the provider once so the periodic timer starts even before the
    // first progress write.
    ref.read(cloudSyncServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      unawaited(ref.read(cloudSyncServiceProvider).syncNow());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CloudSyncService sync = ref.read(cloudSyncServiceProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // The battery-friendly half of the batching contract: one upload per
        // app pause, not one per tap.
        unawaited(sync.syncNow(pull: false));
        break;
      case AppLifecycleState.resumed:
        unawaited(sync.syncNow());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
