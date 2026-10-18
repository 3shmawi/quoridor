import '../../constants.dart';
import '../../models/game_state.dart';
import '../../models/online_chat.dart';
import '../../models/online_session.dart';
import '../turn_clock.dart';

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
    TurnLimit turnLimit = TurnLimit.off,
  }) => {
    'roomCode': roomCode,
    'turnSeconds': turnLimit.seconds,
    'status': OnlineGameStatus.waiting.name,
    'players': {'1': encodePlayer(creator)},
    'playerCount': board.playerCount,
    'currentPlayerId': board.currentPlayerId,
    'moveCount': 0,
    'board': board.toJson(),
    'createdAt': timestamp,
    'updatedAt': timestamp,
  };

  /// The fields written when a player takes [seat].
  ///
  /// The game goes live only once [fillsGame] -- the last empty seat is
  /// taken. Until then it stays findable by its code.
  static Map<String, dynamic> encodeJoin({
    required int seat,
    required OnlinePlayer joiner,
    required bool fillsGame,
    required Object timestamp,
  }) => {
    'players.$seat': encodePlayer(joiner),
    'status':
        (fillsGame ? OnlineGameStatus.active : OnlineGameStatus.waiting).name,
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
        'winner': board.winnerId,
        'reason': OnlineOutcomeReason.goal.name,
      };
    }

    return data;
  }

  /// The fields written when a game ends other than on the board: a player
  /// resigning, claiming the win from one who has gone, or a draw agreed,
  /// which has no [winner].
  static Map<String, dynamic> encodeEnding({
    required int? winner,
    required OnlineOutcomeReason reason,
    required Object timestamp,
  }) => {
    'status': OnlineGameStatus.finished.name,
    'outcome': {'winner': ?winner, 'reason': reason.name},
    'updatedAt': timestamp,
  };

  /// The fields written when [seat] offers a draw at move [atMove].
  static Map<String, dynamic> encodeDrawOffer({
    required int seat,
    required int atMove,
    required Object timestamp,
  }) => {
    'drawOffer': {'by': seat, 'atMove': atMove},
    'updatedAt': timestamp,
  };

  static DrawOffer? decodeDrawOffer(Object? data) {
    if (data is! Map) return null;
    final by = data['by'];
    final atMove = data['atMove'];
    if (by is! int || atMove is! int) return null;
    return DrawOffer(
      by: by,
      atMove: atMove,
      declined: data['declined'] == true,
    );
  }

  /// The fields written when [link] is offered on a finished game.
  static Map<String, dynamic> encodeRematch({
    required RematchLink link,
    required Object timestamp,
  }) => {
    'rematch': {
      'gameId': link.gameId,
      'roomCode': link.roomCode,
      'by': link.by,
    },
    'updatedAt': timestamp,
  };

  static RematchLink? decodeRematch(Object? data) {
    if (data is! Map) return null;
    final gameId = data['gameId'];
    final roomCode = data['roomCode'];
    final by = data['by'];
    if (gameId is! String || roomCode is! String || by is! int) return null;
    return RematchLink(gameId: gameId, roomCode: roomCode, by: by);
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
      playerCount: data['playerCount'] as int? ?? 2,
      currentPlayerId: data['currentPlayerId'] as int? ?? 1,
      moveCount: data['moveCount'] as int? ?? 0,
      board: GameState.fromJson(Map<String, dynamic>.from(boardData)),
      winnerPlayerId: outcome?['winner'] as int?,
      outcomeReason: _decodeReason(outcome?['reason'] as String?),
      updatedAt: _decodeTime(data['updatedAt']),
      rematch: decodeRematch(data['rematch']),
      // Games from before the host chose a limit have none.
      turnLimit: TurnLimit.fromSeconds(data['turnSeconds']),
      drawOffer: decodeDrawOffer(data['drawOffer']),
    );
  }

  /// The fields of one chat message. `uid` is there for the Security Rules,
  /// which check the sender sits in [ChatMessage.seat].
  static Map<String, dynamic> encodeChat({
    required ChatMessage message,
    required String uid,
    required Object sentAt,
  }) => {
    'seat': message.seat,
    'uid': uid,
    'code': message.item?.name ?? ChatMessage.textCode,
    if (message.text case final text?) 'text': text,
    'sentAt': sentAt,
  };

  /// A report of [message] in [gameId]: who reported it, who sent it, and
  /// what it said, copied as it was sent.
  static Map<String, dynamic> encodeReport({
    required String gameId,
    required ChatMessage message,
    required String reporterUid,
    required int reporterSeat,
    required String reportedUid,
    required Object reportedAt,
  }) => {
    'gameId': gameId,
    'messageId': message.id,
    'reporterUid': reporterUid,
    'reporterSeat': reporterSeat,
    'reportedUid': reportedUid,
    'reportedSeat': message.seat,
    'code': message.item?.name ?? ChatMessage.textCode,
    if (message.text case final text?) 'text': text,
    'reportedAt': reportedAt,
  };

  /// Decodes a chat document, or null for one this build cannot show: an
  /// entry added by a newer version, or a malformed write.
  static ChatMessage? decodeChat(String id, Map<String, dynamic> data) {
    final seat = data['seat'];
    if (seat is! int) return null;
    final sentAt = _decodeTime(data['sentAt']);

    if (data['code'] == ChatMessage.textCode) {
      final text = data['text'];
      if (text is! String) return null;
      final tidy = ChatMessage.tidy(text);
      if (tidy.isEmpty) return null;
      return ChatMessage(id: id, seat: seat, text: tidy, sentAt: sentAt);
    }

    final item = QuickChat.tryParse(data['code']);
    if (item == null) return null;
    return ChatMessage(id: id, seat: seat, item: item, sentAt: sentAt);
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
