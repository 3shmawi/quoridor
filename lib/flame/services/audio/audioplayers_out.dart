import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_out.dart';
import 'sfx.dart';

/// The real backend, and the only file that imports an audio package.
///
/// Each effect gets a fixed set of players, created once in [preload] and
/// reused for the life of the app. Nothing is ever created while the game is
/// running: a player per sound is what makes effects arrive late and then
/// stop altogether once the platform runs short of them.
///
/// `AudioPool` from the package is not used on purpose: when all its players
/// are busy it creates another one, so under load it grows without bound.
class AudioplayersOut implements AudioOut {
  final Map<Sfx, List<_Voice>> _voices = {};
  Future<void>? _loading;
  bool _ready = false;

  @override
  Future<void> preload() => _loading ??= _load();

  Future<void> _load() async {
    try {
      await AudioCache.instance.loadAll([
        for (final sfx in Sfx.values) sfx.asset,
      ]);
      for (final sfx in Sfx.values) {
        final voices = <_Voice>[];
        for (var i = 0; i < sfx.voices; i++) {
          final player = AudioPlayer(playerId: '${sfx.name}_$i');
          await player.setReleaseMode(ReleaseMode.stop);
          await player.setPlayerMode(PlayerMode.lowLatency);
          await player.setSource(AssetSource(sfx.asset));
          voices.add(_Voice(player));
        }
        _voices[sfx] = voices;
      }
      _ready = true;
    } catch (error) {
      // No audio device still has to run the game.
      debugPrint('AudioplayersOut: sound disabled, preload failed: $error');
    }
  }

  @override
  void play(Sfx sfx, {double volume = 1}) {
    // Not loaded yet: skip. Falling back to a fresh player here is exactly
    // the leak this class exists to prevent.
    if (!_ready) return;
    final voices = _voices[sfx];
    if (voices == null || voices.isEmpty) return;

    // A voice that has finished needs no rewind. Only when every voice is
    // still ringing is the one that started longest ago cut short.
    final voice = voices.firstWhere(
      (v) => !v.busy,
      orElse: () => _oldest(voices),
    );
    unawaited(voice.start(volume.clamp(0.0, 1.0)));
  }

  static _Voice _oldest(List<_Voice> voices) =>
      voices.reduce((a, b) => a.startedAt.isBefore(b.startedAt) ? a : b);

  @override
  void stopAll() {
    for (final voices in _voices.values) {
      for (final voice in voices) {
        unawaited(voice.stop());
      }
    }
  }
}

class _Voice {
  _Voice(this.player) {
    player.onPlayerComplete.listen((_) => busy = false);
  }

  final AudioPlayer player;
  bool busy = false;
  DateTime startedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start(double volume) async {
    final interrupt = busy;
    busy = true;
    startedAt = DateTime.now();
    try {
      // Low-latency players cannot seek, so a ringing voice is rewound by
      // stopping it. A finished one starts again from the top as it is.
      if (interrupt) await player.stop();
      await player.setVolume(volume);
      await player.resume();
    } catch (error) {
      busy = false;
      debugPrint('AudioplayersOut: play failed: $error');
    }
  }

  Future<void> stop() async {
    busy = false;
    try {
      await player.stop();
    } catch (_) {
      // A player that will not stop is not worth failing the game over.
    }
  }
}
