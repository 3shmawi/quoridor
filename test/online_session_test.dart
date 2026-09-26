import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';

void main() {
  const alice = OnlinePlayer(uid: 'uid-alice', displayName: 'Alice');
  const bob = OnlinePlayer(uid: 'uid-bob', displayName: 'Bob');

  OnlineGame game({
    OnlineGameStatus status = OnlineGameStatus.active,
    int currentPlayerId = 1,
    Map<int, OnlinePlayer>? players,
    int? winnerPlayerId,
  }) => OnlineGame(
    gameId: 'g1',
    roomCode: 'ABCDEF',
    status: status,
    players: players ?? const {1: alice, 2: bob},
    currentPlayerId: currentPlayerId,
    moveCount: 0,
    board: GameStateFactory.createNewGame(player2IsAI: false),
    winnerPlayerId: winnerPlayerId,
  );

  group('seat resolution', () {
    test('resolves each player to their own seat', () {
      expect(game().playerIdOf('uid-alice'), 1);
      expect(game().playerIdOf('uid-bob'), 2);
    });

    test('returns null for someone who is not in the game', () {
      expect(game().playerIdOf('uid-carol'), isNull);
    });

    test('a non-participant session is not a participant', () {
      final session = OnlineSession.forUid(game(), 'uid-carol');
      expect(session.isParticipant, isFalse);
      expect(session.isLocalTurn, isFalse);
    });
  });

  group('turn ownership', () {
    test('the player to move may act', () {
      final session = OnlineSession.forUid(
        game(currentPlayerId: 1),
        'uid-alice',
      );
      expect(session.isLocalTurn, isTrue);
    });

    test('the waiting player may not act on the opponent turn', () {
      // This is the case a hotseat game has no reason to handle: the turn is
      // active, but it is not this device's.
      final session = OnlineSession.forUid(game(currentPlayerId: 1), 'uid-bob');
      expect(session.isLocalTurn, isFalse);
    });

    test('nobody may act while the game is still waiting for an opponent', () {
      final session = OnlineSession.forUid(
        game(status: OnlineGameStatus.waiting, players: const {1: alice}),
        'uid-alice',
      );
      expect(session.isLocalTurn, isFalse);
    });

    test('nobody may act once the game is finished', () {
      final session = OnlineSession.forUid(
        game(status: OnlineGameStatus.finished),
        'uid-alice',
      );
      expect(session.isLocalTurn, isFalse);
    });

    test('nobody may act once the game is abandoned', () {
      final session = OnlineSession.forUid(
        game(status: OnlineGameStatus.abandoned),
        'uid-alice',
      );
      expect(session.isLocalTurn, isFalse);
    });
  });

  group('opponent', () {
    test('each player sees the other as the opponent', () {
      expect(
        OnlineSession.forUid(game(), 'uid-alice').opponent?.displayName,
        'Bob',
      );
      expect(
        OnlineSession.forUid(game(), 'uid-bob').opponent?.displayName,
        'Alice',
      );
    });

    test('there is no opponent until the second seat is taken', () {
      final session = OnlineSession.forUid(
        game(status: OnlineGameStatus.waiting, players: const {1: alice}),
        'uid-alice',
      );
      expect(session.opponent, isNull);
      expect(session.game.hasBothPlayers, isFalse);
    });
  });

  group('outcome', () {
    test('reports the win to the winner and the loss to the loser', () {
      final finished = game(
        status: OnlineGameStatus.finished,
        winnerPlayerId: 1,
      );
      expect(OnlineSession.forUid(finished, 'uid-alice').didWin, isTrue);
      expect(OnlineSession.forUid(finished, 'uid-bob').didWin, isFalse);
    });

    test('is undecided while the game is still running', () {
      expect(OnlineSession.forUid(game(), 'uid-alice').didWin, isNull);
    });
  });
}
