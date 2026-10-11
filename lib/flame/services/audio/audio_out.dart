import 'sfx.dart';

/// Somewhere sound effects go.
///
/// Game code only ever talks to this, never to an audio package, so the real
/// backend can be swapped for a silent or recording one in tests.
abstract interface class AudioOut {
  /// Loads every effect. Safe to call more than once.
  Future<void> preload();

  /// Plays [sfx]. Never throws and never blocks.
  void play(Sfx sfx, {double volume = 1});

  /// Silences anything ringing, e.g. when the app goes to the background.
  void stopAll();
}

/// Plays nothing. The default in tests and wherever audio is unavailable.
class SilentAudio implements AudioOut {
  const SilentAudio();

  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx, {double volume = 1}) {}

  @override
  void stopAll() {}
}

/// Applies mute and volume in one place, read fresh on every play.
class ScaledAudio implements AudioOut {
  ScaledAudio(this.inner, {required this.loudness});

  final AudioOut inner;

  /// 0 for muted, 1 for full volume.
  final double Function() loudness;

  /// Below this a sound is inaudible, so it is not worth a player.
  static const double floor = 0.02;

  @override
  Future<void> preload() => inner.preload();

  @override
  void play(Sfx sfx, {double volume = 1}) {
    final scaled = (volume * loudness()).clamp(0.0, 1.0);
    if (scaled < floor) return;
    inner.play(sfx, volume: scaled);
  }

  @override
  void stopAll() => inner.stopAll();
}
