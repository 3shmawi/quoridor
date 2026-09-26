import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/services/game_service.dart';
import 'package:quoridor/flame/services/online/online_game_codec.dart';

void main() {
  const alice = OnlinePlayer(uid: 'uid-alice', displayName: 'Alice');
  const bob = OnlinePlayer(uid: 'uid-bob', displayName: 'Bob');

  final fixedTime = DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch;

  GameState freshBoard() =>
      GameStateFactory.createNewGame(gameId: 'game-1', player2IsAI: false);

  /// Builds a stored game document the way the service would.
  Map<String, dynamic> gameDoc({
    GameState? board,
    Map<String, dynamic>? players,
    String status = 'active',
    int moveCount = 0,
  }) => {
    'roomCode': 'ABCDEF',
    'status': status,
    'players':
        players ??
        {
          '1': OnlineGameCodec.encodePlayer(alice),
          '2': OnlineGameCodec.encodePlayer(bob),
        },
    'currentPlayerId': 1,
    'moveCount': moveCount,
    'board': (board ?? freshBoard()).toJson(),
    'updatedAt': fixedTime,
  };

  group('move document ids', () {
    test('are zero padded so they sort in play order', () {
      expect(OnlineGameCodec.moveDocId(0), '000000');
      expect(OnlineGameCodec.moveDocId(7), '000007');
      expect(OnlineGameCodec.moveDocId(123), '000123');
    });

    test('sort lexically in numeric order', () {
      final ids = [
        0,
        1,
        2,
        9,
        10,
        11,
        99,
        100,
      ].map(OnlineGameCodec.moveDocId).toList();
      final sorted = [...ids]..sort();
      expect(sorted, ids);
    });
  });

  group('move encoding', () {
    test('round-trips a pawn move', () {
      const move = GameMove.pawnMove(Position(5, 4), 1);
      final encoded = OnlineGameCodec.encodeMove(
        move: move,
        submittedBy: 'uid-alice',
        submittedAt: fixedTime,
      );

      expect(encoded['submittedBy'], 'uid-alice');

      final decoded = OnlineGameCodec.decodeMove(encoded);
      expect(decoded.type, MoveType.pawnMove);
      expect(decoded.newPosition, const Position(5, 4));
      expect(decoded.playerId, 1);
    });

    test('round-trips a wall placement including orientation', () {
      const move = GameMove.wallPlace(
        Wall(Position(4, 3), WallOrientation.vertical),
        2,
      );
      final decoded = OnlineGameCodec.decodeMove(
        OnlineGameCodec.encodeMove(
          move: move,
          submittedBy: 'uid-bob',
          submittedAt: fixedTime,
        ),
      );

      expect(decoded.type, MoveType.wallPlace);
      expect(decoded.wall?.position, const Position(4, 3));
      expect(decoded.wall?.orientation, WallOrientation.vertical);
      expect(decoded.playerId, 2);
    });
  });

  group('new game encoding', () {
    test('seats the creator as player 1 and leaves seat 2 empty', () {
      final encoded = OnlineGameCodec.encodeNewGame(
        roomCode: 'ABCDEF',
        creator: alice,
        board: freshBoard(),
        timestamp: fixedTime,
      );

      expect(encoded['status'], 'waiting');
      expect(encoded['moveCount'], 0);
      expect((encoded['players'] as Map).keys, ['1']);
      expect((encoded['players'] as Map)['1']['uid'], 'uid-alice');
    });
  });

  group('join encoding', () {
    test('writes seat 2 with a dotted path so seat 1 is untouched', () {
      final encoded = OnlineGameCodec.encodeJoin(
        joiner: bob,
        timestamp: fixedTime,
      );

      // A dotted key updates just that field; a nested map would replace the
      // whole players object and wipe player 1.
      expect(encoded.containsKey('players.2'), isTrue);
      expect(encoded.containsKey('players'), isFalse);
      expect(encoded['status'], 'active');
    });
  });

  group('move result encoding', () {
    test('advances the counter and the turn', () {
      final board = GameService.executeMove(
        freshBoard(),
        const GameMove.pawnMove(Position(7, 4), 1),
      );

      final encoded = OnlineGameCodec.encodeMoveResult(
        board: board,
        moveCount: 1,
        timestamp: fixedTime,
      );

      expect(encoded['moveCount'], 1);
      expect(encoded['currentPlayerId'], 2);
      expect(encoded.containsKey('outcome'), isFalse);
      expect(encoded.containsKey('status'), isFalse);
    });

    test('records the winner when the move ends the game', () {
      // Put player 1 one step from their goal row, then step onto it.
      final board = freshBoard();
      board.player1.moveTo(const Position(1, 0));
      board.player2.moveTo(const Position(5, 8));

      final won = GameService.executeMove(
        board,
        const GameMove.pawnMove(Position(0, 0), 1),
      );
      expect(won.isGameOver, isTrue);

      final encoded = OnlineGameCodec.encodeMoveResult(
        board: won,
        moveCount: 1,
        timestamp: fixedTime,
      );

      expect(encoded['status'], 'finished');
      expect((encoded['outcome'] as Map)['winner'], 1);
      expect((encoded['outcome'] as Map)['reason'], 'goal');
    });
  });

  group('game decoding', () {
    test('round-trips a document written by the encoders', () {
      final decoded = OnlineGameCodec.decodeGame('game-1', gameDoc());

      expect(decoded.gameId, 'game-1');
      expect(decoded.roomCode, 'ABCDEF');
      expect(decoded.status, OnlineGameStatus.active);
      expect(decoded.players[1]?.displayName, 'Alice');
      expect(decoded.players[2]?.displayName, 'Bob');
      expect(decoded.board.player1.position, GameConstants.player1Start);
    });

    test('preserves walls placed on the board', () {
      final board = GameService.executeMove(
        freshBoard(),
        const GameMove.wallPlace(
          Wall(Position(4, 3), WallOrientation.horizontal),
          1,
        ),
      );

      final decoded = OnlineGameCodec.decodeGame(
        'game-1',
        gameDoc(board: board),
      );

      expect(decoded.board.walls, hasLength(1));
      expect(decoded.board.walls.first.position, const Position(4, 3));
      expect(decoded.board.player1.wallsRemaining, 9);
    });

    test('tolerates an unknown status rather than throwing', () {
      final decoded = OnlineGameCodec.decodeGame(
        'game-1',
        gameDoc(status: 'something-newer'),
      );
      expect(decoded.status, OnlineGameStatus.waiting);
    });

    test('tolerates a game with only one seat filled', () {
      final decoded = OnlineGameCodec.decodeGame(
        'game-1',
        gameDoc(
          status: 'waiting',
          players: {'1': OnlineGameCodec.encodePlayer(alice)},
        ),
      );

      expect(decoded.hasBothPlayers, isFalse);
      expect(decoded.playerIdOf('uid-alice'), 1);
    });

    test('rejects a document with no board instead of a cast error', () {
      final broken = gameDoc()..remove('board');
      expect(
        () => OnlineGameCodec.decodeGame('game-1', broken),
        throwsA(isA<OnlineGameFormatException>()),
      );
    });
  });
}
