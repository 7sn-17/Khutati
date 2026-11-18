import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/theme_mode_controller.dart' show sharedPreferencesProvider;

/// Whether Khutati is allowed to play its UI sounds.
final NotifierProvider<SoundEffectsController, bool>
soundEffectsEnabledProvider = NotifierProvider<SoundEffectsController, bool>(
  SoundEffectsController.new,
);

class SoundEffectsController extends Notifier<bool> {
  @override
  bool build() {
    final bool enabled =
        ref.watch(sharedPreferencesProvider).getBool(SoundEffects.storageKey) ??
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
  }
}

/// The four UI sounds, each with its own pre-loaded player.
///
/// The loudness lives in the WAV files, not here. On Android the low-latency
/// path (SoundPool) applies gain when a sample is loaded, so
/// `AudioPlayer.setVolume` never reached the mix — two releases shipped a
/// quieter constant and played exactly the same level. `tools/master_sounds.mjs`
/// normalises the assets to a fixed peak instead, which no platform path can
/// skip.
enum KSound {
  /// Soft wooden click: buttons, list rows, modal actions.
  tap('sounds/click.wav'),

  /// Short "tock": switches and the 4-tap step cycle.
  toggle('sounds/toggle.wav'),

  /// Gentle chime: a step or a focus session is completed.
  success('sounds/success.wav'),

  /// Soft whoosh: starting or stopping a focus session.
  timer('sounds/timer.wav');

  const KSound(this.asset);

  final String asset;
}

/// Small, bundled sounds played through one pre-loaded player each.
///
/// All four are prepared once at startup so a tap never waits on decoding. The
/// mix is mastered into the assets (−24 dBFS for taps, −21 for the chime,
/// −26 for the timer) rather than set at runtime; see [KSound].
abstract final class SoundEffects {
  static const String storageKey = 'sound_effects_enabled';

  static bool enabled = true;

  static final Map<KSound, AudioPlayer> _players = <KSound, AudioPlayer>{};
  static final Set<KSound> _ready = <KSound>{};

  /// Startup and the settings provider both ask for preparation; sharing one
  /// future stops them from configuring the same player concurrently.
  static Future<void>? _preparing;

  static Future<void> init({required bool enabled}) async {
    SoundEffects.enabled = enabled;
    await prepare();
  }

  static Future<void> prepare() => _preparing ??= _prepareAll();

  static Future<void> _prepareAll() async {
    for (final KSound sound in KSound.values) {
      if (_ready.contains(sound)) continue;
      final AudioPlayer player = _players[sound] ?? AudioPlayer();
      _players[sound] = player;
      try {
        // Low-latency mode uses Android's SoundPool: the sample is decoded once
        // and replayed without touching the media pipeline. No `setVolume`
        // here on purpose — see [KSound]: the gain is in the file.
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(sound.asset));
        _ready.add(sound);
      } catch (_) {
        // A device without an audio sink must never break a tap.
      }
    }
  }

  static void play(KSound sound) {
    if (!enabled || !_ready.contains(sound)) return;
    final AudioPlayer? player = _players[sound];
    if (player == null) return;
    unawaited(_replay(player));
  }

  static void tap() => play(KSound.tap);

  static void toggle() => play(KSound.toggle);

  static void success() => play(KSound.success);

  static void timer() => play(KSound.timer);

  static Future<void> _replay(AudioPlayer player) async {
    try {
      await player.stop();
      await player.resume();
    } catch (_) {
      // Best-effort audio: UI actions stay fully functional when it fails.
    }
  }

  static Future<void> dispose() async {
    for (final AudioPlayer player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _ready.clear();
    _preparing = null;
  }
}
