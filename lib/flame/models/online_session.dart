import 'package:flutter/foundation.dart';

import 'game_state.dart';

/// Lifecycle of an online game.
enum OnlineGameStatus {
  /// Created, with one seat still empty.
  waiting,

  /// Both seats filled; moves are being played.
  active,

  /// Someone won, resigned or the game was drawn.
  finished,

  /// Given up on without finishing.
  abandoned;

  static OnlineGameStatus fromName(String? value) {
    return OnlineGameStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => OnlineGameStatus.waiting,
    );
  }
}

/// Why an online game ended.
enum OnlineOutcomeReason { goal, resign, timeout, draw }

/// One seat in an online game.
@immutable
class OnlinePlayer {
  final String uid;
  final String displayName;

  /// Whether this player's client is currently reporting in. Presence is
  /// maintained in a later phase; until then it stays at its written value.
  final bool connected;

  final DateTime? lastSeen;

  const OnlinePlayer({
    required this.uid,
    required this.displayName,
    this.connected = false,
    this.lastSeen,
  });

  @override
  bool operator ==(Object other) =>
      other is OnlinePlayer &&
      other.uid == uid &&
      other.displayName == displayName &&
      other.connected == connected &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(uid, displayName, connected, lastSeen);
}

/// A snapshot of an online game as the server currently holds it.
@immutable
class OnlineGame {
  final String gameId;
  final String roomCode;
  final OnlineGameStatus status;

  /// Seats, keyed by the same player numbers the rules use: 1 and 2.
  final Map<int, OnlinePlayer> players;

  final int currentPlayerId;

  /// Number of moves played. Doubles as the optimistic-lock token: a move is
  /// written only if the count is still what the submitting client saw.
  final int moveCount;

  /// The board as the server last recorded it. This is a cache of replaying
  /// the move list, kept so a joining client can render without replaying.
  final GameState board;

  final int? winnerPlayerId;
  final OnlineOutcomeReason? outcomeReason;
  final DateTime? updatedAt;

  const OnlineGame({
    required this.gameId,
    required this.roomCode,
    required this.status,
    required this.players,
    required this.currentPlayerId,
    required this.moveCount,
    required this.board,
    this.winnerPlayerId,
    this.outcomeReason,
    this.updatedAt,
  });

  bool get isOver =>
      status == OnlineGameStatus.finished ||
      status == OnlineGameStatus.abandoned;

  bool get hasBothPlayers => players.containsKey(1) && players.containsKey(2);

  /// The seat [uid] occupies, or null when they are not in this game.
  int? playerIdOf(String uid) {
    for (final entry in players.entries) {
      if (entry.value.uid == uid) return entry.key;
    }
    return null;
  }
}

/// An online game as seen from one device.
///
/// This is what makes remote play different from a game on one device: a
/// hotseat client accepts input whenever the game is not over, while an online
/// client must also refuse input during the opponent's turn, even though that
/// turn is perfectly active.
@immutable
class OnlineSession {
  final OnlineGame game;

  /// Which seat this device plays. Null when watching a game it is not in.
  final int? localPlayerId;

  const OnlineSession({required this.game, required this.localPlayerId});

  /// Builds a session for [uid], resolving which seat they hold.
  factory OnlineSession.forUid(OnlineGame game, String uid) =>
      OnlineSession(game: game, localPlayerId: game.playerIdOf(uid));

  bool get isParticipant => localPlayerId != null;

  /// Whether this device may act right now.
  bool get isLocalTurn =>
      isParticipant &&
      game.status == OnlineGameStatus.active &&
      game.currentPlayerId == localPlayerId;

  /// The opponent's seat, if both are filled.
  OnlinePlayer? get opponent {
    final id = localPlayerId;
    if (id == null) return null;
    return game.players[id == 1 ? 2 : 1];
  }

  OnlinePlayer? get localPlayer =>
      localPlayerId == null ? null : game.players[localPlayerId];

  /// Whether this device won, once the game is over.
  bool? get didWin {
    if (!game.isOver || game.winnerPlayerId == null || !isParticipant) {
      return null;
    }
    return game.winnerPlayerId == localPlayerId;
  }

  OnlineSession copyWith({OnlineGame? game}) =>
      OnlineSession(game: game ?? this.game, localPlayerId: localPlayerId);
}
