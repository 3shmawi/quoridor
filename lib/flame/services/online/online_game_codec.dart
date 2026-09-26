import '../../constants.dart';
import '../../models/game_state.dart';
import '../../models/online_session.dart';

/// Translates between the game's own types and the documents stored for an
/// online game.
///
/// Kept free of any Firestore import so the wire format can be tested
/// directly, and so the same encoding can be reused by a server-side
/// validator later without dragging the client SDK along.
class OnlineGameCodec {
  OnlineGameCodec._();

  /// Width of the zero-padded move document id.
  ///
  /// Move documents are named by their index so the collection sorts in play
  /// order lexically, which is the only ordering Firestore gives for free.
  /// Six digits covers any plausible game; Quoridor rarely passes 100 moves.
  static const int moveIdWidth = 6;

  /// Document id for the move at [index].
  static String moveDocId(int index) =>
      index.toString().padLeft(moveIdWidth, '0');

  /// Encodes a move, plus who submitted it.
  ///
  /// [submittedAt] is left to the caller so production code can pass a server
  /// timestamp while tests pass a fixed value.
  static Map<String, dynamic> encodeMove({
    required GameMove move,
    required String submittedBy,
    required Object submittedAt,
  }) => {
    ...move.toJson(),
    'submittedBy': submittedBy,
    'submittedAt': submittedAt,
  };

  /// Decodes a move document back into a [GameMove].
  static GameMove decodeMove(Map<String, dynamic> data) =>
      GameMove.fromJson(data);

  /// The fields written when a game is first created.
  static Map<String, dynamic> encodeNewGame({
    required String roomCode,
    required OnlinePlayer creator,
    required GameState board,
    required Object timestamp,
  }) => {
    'roomCode': roomCode,
    'status': OnlineGameStatus.waiting.name,
    'players': {'1': encodePlayer(creator)},
    'currentPlayerId': board.currentPlayerId,
    'moveCount': 0,
    'board': board.toJson(),
    'createdAt': timestamp,
    'updatedAt': timestamp,
  };

  /// The fields written when the second player takes their seat.
  static Map<String, dynamic> encodeJoin({
    required OnlinePlayer joiner,
    required Object timestamp,
  }) => {
    'players.2': encodePlayer(joiner),
    'status': OnlineGameStatus.active.name,
    'updatedAt': timestamp,
  };

  /// The fields written when a move is accepted.
  static Map<String, dynamic> encodeMoveResult({
    required GameState board,
    required int moveCount,
    required Object timestamp,
  }) {
    final data = <String, dynamic>{
      'board': board.toJson(),
      'currentPlayerId': board.currentPlayerId,
      'moveCount': moveCount,
      'updatedAt': timestamp,
    };

    if (board.isGameOver) {
      data['status'] = OnlineGameStatus.finished.name;
      data['outcome'] = {
        'winner': board.status == GameStatus.player1Won ? 1 : 2,
        'reason': OnlineOutcomeReason.goal.name,
      };
    }

    return data;
  }

  static Map<String, dynamic> encodePlayer(OnlinePlayer player) => {
    'uid': player.uid,
    'displayName': player.displayName,
    'connected': player.connected,
    'lastSeen': player.lastSeen?.millisecondsSinceEpoch,
  };

  static OnlinePlayer decodePlayer(Map<String, dynamic> data) => OnlinePlayer(
    uid: data['uid'] as String? ?? '',
    displayName: data['displayName'] as String? ?? 'Player',
    connected: data['connected'] as bool? ?? false,
    lastSeen: _decodeTime(data['lastSeen']),
  );

  /// Decodes a whole game document.
  ///
  /// Every field is read defensively: a document may have been written by an
  /// older build, or by a client that is ahead of this one.
  static OnlineGame decodeGame(String gameId, Map<String, dynamic> data) {
    final playersData = (data['players'] as Map?) ?? const {};
    final players = <int, OnlinePlayer>{};

    for (final entry in playersData.entries) {
      final seat = int.tryParse(entry.key.toString());
      final value = entry.value;
      if (seat == null || value is! Map) continue;
      players[seat] = decodePlayer(Map<String, dynamic>.from(value));
    }

    final boardData = data['board'];
    if (boardData is! Map || boardData['gameId'] == null) {
      // Without a board there is nothing to render; say so plainly rather
      // than letting GameState.fromJson fail with a cast error.
      throw const OnlineGameFormatException('game document has no board');
    }

    final outcome = data['outcome'] as Map?;

    return OnlineGame(
      gameId: gameId,
      roomCode: data['roomCode'] as String? ?? '',
      status: OnlineGameStatus.fromName(data['status'] as String?),
      players: players,
      currentPlayerId: data['currentPlayerId'] as int? ?? 1,
      moveCount: data['moveCount'] as int? ?? 0,
      board: GameState.fromJson(Map<String, dynamic>.from(boardData)),
      winnerPlayerId: outcome?['winner'] as int?,
      outcomeReason: _decodeReason(outcome?['reason'] as String?),
      updatedAt: _decodeTime(data['updatedAt']),
    );
  }

  static OnlineOutcomeReason? _decodeReason(String? value) {
    if (value == null) return null;
    for (final reason in OnlineOutcomeReason.values) {
      if (reason.name == value) return reason;
    }
    return null;
  }

  /// Accepts either a millisecond epoch or anything exposing `toDate()`,
  /// which is how a Firestore timestamp arrives.
  static DateTime? _decodeTime(Object? value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}

/// Thrown when a stored game document cannot be read.
class OnlineGameFormatException implements Exception {
  final String message;

  const OnlineGameFormatException(this.message);

  @override
  String toString() => 'OnlineGameFormatException: $message';
}
