import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True once the launch sequence (native splash → Flutter splash) is over.
///
/// Two app-level surfaces want to interrupt the user: the update dialog and the
/// notification-permission prompt. Both are correct on Today and both are wrong
/// on top of the splash, so they wait for this gate instead of a timer.
final NotifierProvider<LaunchGate, bool> launchReadyProvider =
    NotifierProvider<LaunchGate, bool>(LaunchGate.new);

class LaunchGate extends Notifier<bool> {
  @override
  bool build() => false;

  void complete() {
    if (!state) state = true;
  }
}
