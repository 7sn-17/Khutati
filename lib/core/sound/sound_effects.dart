import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/theme_mode_controller.dart' show sharedPreferencesProvider;

/// Whether Khutati is allowed to play its two UI sounds.
final NotifierProvider<SoundEffectsController, bool> soundEffectsEnabledProvider =
    NotifierProvider<SoundEffectsController, bool>(SoundEffectsController.new);

class SoundEffectsController extends Notifier<bool> {
  @override
  bool build() {
    final bool enabled = ref
        .watch(sharedPreferencesProvider)
        .getBool(SoundEffects.storageKey) ??
        true;
    SoundEffects.enabled = enabled;
    unawaited(SoundEffects.prepare());
    return enabled;
  }

  Future<void> set(bool value) async {
    state = value;
    SoundEffects.enabled = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(SoundEffects.storageKey, value);
    if (value) SoundEffects.click();
  }
}

/// Two tiny, bundled sounds: a soft tap and a short completion chime.
///
/// They are preloaded once so a button press starts the sample immediately;
/// no network, no platform music player, no permission.
abstract final class SoundEffects {
  static const String storageKey = 'sound_effects_enabled';

  static bool enabled = true;
  static final AudioPlayer _click = AudioPlayer();
  static final AudioPlayer _success = AudioPlayer();
  static bool _ready = false;

  static Future<void> init({required bool enabled}) async {
    SoundEffects.enabled = enabled;
    await prepare();
  }

  static Future<void> prepare() async {
    if (_ready) return;
    try {
      await _click.setPlayerMode(PlayerMode.lowLatency);
      await _click.setReleaseMode(ReleaseMode.stop);
      await _click.setVolume(0.42);
      await _click.setSource(AssetSource('sounds/click.wav'));

      await _success.setReleaseMode(ReleaseMode.stop);
      await _success.setVolume(0.34);
      await _success.setSource(AssetSource('sounds/success.wav'));
      _ready = true;
    } catch (_) {
      // A device without an audio sink must never break a tap.
    }
  }

  static void click() {
    if (!enabled || !_ready) return;
    unawaited(_replay(_click));
  }

  static void success() {
    if (!enabled || !_ready) return;
    unawaited(_replay(_success));
  }

  static Future<void> _replay(AudioPlayer player) async {
    try {
      await player.stop();
      await player.resume();
    } catch (_) {
      // Best-effort audio: UI actions stay fully functional when it fails.
    }
  }

  static Future<void> dispose() async {
    await _click.dispose();
    await _success.dispose();
  }
}
