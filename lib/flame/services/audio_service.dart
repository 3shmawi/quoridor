import 'package:flutter/foundation.dart';

import 'audio/audio_out.dart';
import 'audio/audioplayers_out.dart';
import 'audio/sfx.dart';

export 'audio/sfx.dart';

/// The app's sound, wired once: the real backend behind the player's
/// sound setting.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  /// Whether the player wants sound.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  late AudioOut _out = ScaledAudio(
    AudioplayersOut(),
    loudness: () => enabled.value ? 1 : 0,
  );

  /// Replaces the backend; tests pass a recording fake.
  @visibleForTesting
  set debugOut(AudioOut out) =>
      _out = ScaledAudio(out, loudness: () => enabled.value ? 1 : 0);

  /// Loads every effect. On the web this waits for the first tap or key,
  /// since browsers refuse audio before one.
  Future<void> initialize() => _out.preload();

  void play(Sfx sfx) => _out.play(sfx);

  void stopAll() => _out.stopAll();
}
