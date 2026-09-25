import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The sound effects the game can play.
enum GameSound {
  movePlayer1('sounds/move_player1.wav'),
  movePlayer2('sounds/move_player2.wav'),
  wallPlayer1('sounds/wall_player1.wav'),
  wallPlayer2('sounds/wall_player2.wav'),
  win('sounds/win.wav');

  const GameSound(this.asset);

  final String asset;

  static GameSound move(int playerId) =>
      playerId == 1 ? GameSound.movePlayer1 : GameSound.movePlayer2;

  static GameSound wall(int playerId) =>
      playerId == 1 ? GameSound.wallPlayer1 : GameSound.wallPlayer2;
}

/// Plays the game's sound effects.
///
/// The previous implementation created an [AudioPlayer] per component and
/// called `play(AssetSource(...))` for every single effect. Each of those calls
/// re-resolves the asset and spins up a fresh native player; on Android that
/// allocates a `MediaPlayer` per call, and the platform runs out of them after
/// a few dozen moves, which is what made long games crash.
///
/// Instead this service:
///  * keeps one shared, app-wide instance,
///  * pre-loads every effect once into a small fixed pool of reusable players,
///  * uses [PlayerMode.lowLatency], the mode intended for short effects,
///  * never allocates while the game is running, so play count cannot leak,
///  * swallows playback errors and disables itself after repeated failures
///    rather than letting an audio fault take the game down.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  /// Players kept per sound. Two is enough for a board game: it lets a new
  /// effect start while the previous one is still ringing out, without ever
  /// growing the number of native players.
  static const int _playersPerSound = 2;

  /// Identical effects fired closer together than this are dropped. Guards
  /// against a stuck UI or a fast tapper flooding the audio backend.
  static const Duration _minGapBetweenRepeats = Duration(milliseconds: 60);

  bool _initialised = false;
  bool _disposed = false;
  Future<void>? _initialisation;

  /// Turns audio off for the rest of the session once the backend has proven
  /// unreliable, so a broken device degrades to a silent game, not a crash.
  bool _failed = false;
  int _consecutiveFailures = 0;
  static const int _failureLimit = 5;

  final Map<GameSound, List<AudioPlayer>> _pool = {};
  final Map<GameSound, int> _nextPlayer = {};
  final Map<GameSound, DateTime> _lastPlayed = {};

  /// Whether the player wants sound. Exposed as a notifier so UI can bind to it.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// True when audio has been permanently disabled after repeated failures.
  bool get isUnavailable => _failed;

  /// Loads every effect. Safe to call more than once; concurrent calls share
  /// the same future.
  Future<void> initialize() {
    if (_initialised || _failed || _disposed) return Future<void>.value();
    return _initialisation ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      for (final sound in GameSound.values) {
        final players = <AudioPlayer>[];
        for (var i = 0; i < _playersPerSound; i++) {
          final player = AudioPlayer(playerId: '${sound.name}_$i');
          await player.setReleaseMode(ReleaseMode.stop);
          await player.setPlayerMode(PlayerMode.lowLatency);
          // Resolve and buffer the asset once, up front.
          await player.setSource(AssetSource(sound.asset));
          players.add(player);
        }
        _pool[sound] = players;
        _nextPlayer[sound] = 0;
      }
      _initialised = true;
    } catch (error, stackTrace) {
      _failed = true;
      await _releasePlayers();
      debugPrint(
        'AudioService: disabling sound, initialisation failed: $error',
      );
      assert(() {
        debugPrintStack(stackTrace: stackTrace);
        return true;
      }());
    } finally {
      _initialisation = null;
    }
  }

  /// Plays [sound]. Never throws and never blocks the caller.
  void play(GameSound sound) {
    if (_disposed || _failed || !enabled.value) return;

    final now = DateTime.now();
    final last = _lastPlayed[sound];
    if (last != null && now.difference(last) < _minGapBetweenRepeats) return;
    _lastPlayed[sound] = now;

    unawaited(_play(sound));
  }

  Future<void> _play(GameSound sound) async {
    try {
      if (!_initialised) {
        await initialize();
        if (!_initialised || _failed) return;
      }

      final players = _pool[sound];
      if (players == null || players.isEmpty) return;

      final index = _nextPlayer[sound] ?? 0;
      _nextPlayer[sound] = (index + 1) % players.length;
      final player = players[index];

      // Restart from the beginning. Low-latency players do not support seek,
      // so the effect is rewound by stopping first.
      await player.stop();
      if (_disposed) return;
      await player.resume();

      _consecutiveFailures = 0;
    } catch (error) {
      _consecutiveFailures++;
      debugPrint('AudioService: failed to play ${sound.name}: $error');
      if (_consecutiveFailures >= _failureLimit) {
        _failed = true;
        debugPrint('AudioService: too many failures, sound disabled.');
        await _releasePlayers();
      }
    }
  }

  /// Stops anything currently playing without tearing the service down.
  Future<void> stopAll() async {
    for (final players in _pool.values) {
      for (final player in players) {
        try {
          await player.stop();
        } catch (_) {
          // A player that will not stop is not worth failing the game over.
        }
      }
    }
  }

  Future<void> _releasePlayers() async {
    for (final players in _pool.values) {
      for (final player in players) {
        try {
          await player.dispose();
        } catch (_) {
          // Already gone.
        }
      }
    }
    _pool.clear();
    _nextPlayer.clear();
    _initialised = false;
  }

  /// Releases every native player. Called when the app shuts down; individual
  /// screens must not call this, since the service is shared.
  Future<void> dispose() async {
    _disposed = true;
    await _releasePlayers();
  }
}
