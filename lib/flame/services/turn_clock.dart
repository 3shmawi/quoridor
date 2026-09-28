import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long a player gets for one turn.
///
/// A budget for the whole game was the other option, and was rejected: this
/// is a phone game people play in short sittings, where a game-long clock
/// punishes putting the phone down far more than it discourages stalling.
/// A per-turn limit starts fresh every turn, so only the turn in front of you
/// is ever at stake.
enum TurnLimit {
  off,
  fifteenSeconds,
  thirtySeconds,
  sixtySeconds;

  /// The limit as a duration, or null when the clock is off.
  Duration? get duration {
    switch (this) {
      case TurnLimit.off:
        return null;
      case TurnLimit.fifteenSeconds:
        return const Duration(seconds: 15);
      case TurnLimit.thirtySeconds:
        return const Duration(seconds: 30);
      case TurnLimit.sixtySeconds:
        return const Duration(seconds: 60);
    }
  }

  /// The number shown in the settings list, in seconds.
  int get seconds => duration?.inSeconds ?? 0;
}

/// Counts down the turn in front of the player.
///
/// The countdown is driven by a deadline rather than by subtracting from a
/// balance on every tick: a phone that sleeps, a frame that takes too long or
/// a browser tab in the background all delay ticks, and a balance built out of
/// them drifts further from the truth the longer the turn runs. Reading the
/// clock instead means a late tick is merely late, never wrong.
class TurnClock {
  TurnClock({DateTime Function()? now, this.tickInterval = _defaultTick})
    : _now = now ?? DateTime.now;

  static const Duration _defaultTick = Duration(milliseconds: 200);

  final DateTime Function() _now;

  /// How often [remaining] is refreshed while a turn is running.
  final Duration tickInterval;

  /// Time left in the current turn, or null when no turn is being timed.
  final ValueNotifier<Duration?> remaining = ValueNotifier<Duration?>(null);

  /// Called once when a turn's time runs out.
  VoidCallback? onExpired;

  TurnLimit _limit = TurnLimit.off;
  Object? _turnKey;
  DateTime? _deadline;
  Timer? _ticker;
  bool _disposed = false;

  TurnLimit get limit => _limit;

  /// Whether a turn is currently being timed.
  bool get isRunning => _deadline != null;

  set limit(TurnLimit value) {
    if (_limit == value) return;
    _limit = value;

    // Changing the limit mid-turn restarts the turn rather than rescaling what
    // is left of it, which would hand somebody a shorter turn than the setting
    // they just chose.
    final key = _turnKey;
    if (key == null) return;
    _turnKey = null;
    beginTurn(key);
  }

  /// Starts timing [turnKey], or leaves a turn already being timed alone.
  ///
  /// The caller can hand the same key over on every rebuild: only a key it has
  /// not seen starts the clock again. That keeps the countdown from jumping
  /// back to full whenever something unrelated redraws the screen.
  void beginTurn(Object turnKey) {
    if (_disposed) return;
    if (_turnKey == turnKey && _deadline != null) return;

    _turnKey = turnKey;

    final duration = _limit.duration;
    if (duration == null) {
      _stopTicking();
      _deadline = null;
      remaining.value = null;
      return;
    }

    _deadline = _now().add(duration);
    remaining.value = duration;
    _startTicking();
  }

  /// Stops timing, leaving nothing on the clock — between games, or while it
  /// is nobody's turn to act.
  void stop() {
    _stopTicking();
    _turnKey = null;
    _deadline = null;
    remaining.value = null;
  }

  /// Refreshes [remaining], firing [onExpired] the first time it hits zero.
  ///
  /// Public so tests can drive the countdown without waiting out a real turn.
  void tick() {
    final deadline = _deadline;
    if (deadline == null) return;

    final left = deadline.difference(_now());
    if (left > Duration.zero) {
      remaining.value = left;
      return;
    }

    // Clearing the deadline before the callback means a handler that starts
    // the next turn is not immediately undone by this one, and that a handler
    // which does nothing cannot be called twice for the same turn.
    _stopTicking();
    _deadline = null;
    remaining.value = Duration.zero;
    onExpired?.call();
  }

  void _startTicking() {
    _ticker ??= Timer.periodic(tickInterval, (_) => tick());
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  void dispose() {
    _disposed = true;
    _stopTicking();
    remaining.dispose();
  }
}
