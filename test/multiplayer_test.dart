import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/ai/quoridor_engine.dart';
import 'package:quoridor/flame/services/game_service.dart';

void main() {
  group('setting the table', () {
    test('two players still start exactly as they did', () {
      final state = GameStateFactory.createNewGame();

      expect(state.playerCount, 2);
      expect(state.player1.position, GameConstants.player1Start);
      expect(state.player2.position, GameConstants.player2Start);
      expect(state.player1.goal, GoalEdge.top);
      expect(state.player2.goal, GoalEdge.bottom);
      expect(state.players.every((p) => p.wallsRemaining == 10), isTrue);
    });

    for (final count in [3, 4]) {
      test('$count players each get a side and a corner of the board', () {
        final state = GameStateFactory.createNewGame(playerCount: count);

        expect(state.playerCount, count);
        expect(state.players.map((p) => p.id).toList(), [
          for (var i = 1; i <= count; i++) i,
        ]);

        // Everybody aims at the edge opposite the one they start on.
        for (final player in state.players) {
          expect(player.goal, GoalEdge.homeOfSeat(player.id).opposite);
          expect(
            GoalEdge.homeOfSeat(player.id).contains(player.position),
            isTrue,
          );
        }

        // Nobody shares a square.
        final squares = state.players.map((p) => p.position).toSet();
        expect(squares.length, count);
      });
    }

    test('walls are shared out so the board cannot be turned into a maze', () {
      expect(GameStateFactory.createNewGame().player1.wallsRemaining, 10);
      expect(
        GameStateFactory.createNewGame(playerCount: 3).player1.wallsRemaining,
        7,
      );
      expect(
        GameStateFactory.createNewGame(playerCount: 4).player1.wallsRemaining,
        5,
      );
    });
  });

  group('taking turns', () {
    for (final count in [2, 3, 4]) {
      test('$count players take turns in seat order and wrap round', () {
        final state = GameStateFactory.createNewGame(playerCount: count);
        final seen = <int>[];

        for (var i = 0; i < count * 2; i++) {
          seen.add(state.currentPlayerId);
          state.switchTurn();
        }

        final oneRound = [for (var i = 1; i <= count; i++) i];
        expect(seen, [...oneRound, ...oneRound]);
      });
    }
  });

  group('the sealed-in rule', () {
    test('a wall that shuts seat three in is refused', () {
      final state = GameStateFactory.createNewGame(playerCount: 4);

      // Box seat three, who starts at (4,0), into a two-square pocket. A
      // single square cannot be closed off: the two walls that would do it
      // share a centre point, which the crossing rule rightly refuses.
      state.walls.addAll(const [
        Wall(Position(4, 0), WallOrientation.horizontal),
        Wall(Position(6, 0), WallOrientation.horizontal),
      ]);

      // The last side of the pocket, which leaves seat three no way out to
      // the right-hand column it is racing for.
      const sealing = Wall(Position(4, 1), WallOrientation.vertical);
      final result = GameService.validateWallPlacement(
        state,
        state.player1,
        sealing,
      );

      expect(result.isValid, isFalse);
      expect(result.rejection, WallRejection.blocksPlayer);
    });

    test('a wall that merely lengthens seat three\'s route is allowed', () {
      final state = GameStateFactory.createNewGame(playerCount: 4);
      const wall = Wall(Position(4, 1), WallOrientation.vertical);

      expect(
        GameService.validateWallPlacement(state, state.player1, wall).isValid,
        isTrue,
      );
    });
  });

  group('winning', () {
    test('seat three wins by reaching the right-hand column', () {
      final state = GameStateFactory.createNewGame(playerCount: 4);
      final seatThree = state.playerById(3);

      seatThree.moveTo(const Position(4, GameConstants.boardSize - 1));
      state.checkWinCondition();

      expect(state.isGameOver, isTrue);
      expect(state.winnerId, 3);
      expect(state.winner, seatThree.name);
    });

    test('seat four wins by reaching the left-hand column', () {
      final state = GameStateFactory.createNewGame(playerCount: 4);

      state.playerById(4).moveTo(const Position(4, 0));
      state.checkWinCondition();

      expect(state.winnerId, 4);
    });

    test('reaching the wrong edge wins nothing', () {
      final state = GameStateFactory.createNewGame(playerCount: 4);

      // Seat three is racing right, so the left column is its own doorstep.
      state.playerById(3).moveTo(const Position(0, 0));
      state.checkWinCondition();

      expect(state.isGameOver, isFalse);
    });
  });

  group('the computer at a crowded board', () {
    for (final count in [3, 4]) {
      test('a $count player game is played to a finish', () {
        var state = GameStateFactory.createNewGame(playerCount: count);
        var plies = 0;

        while (!state.isGameOver && plies < 400) {
          final move = QuoridorEngine.bestMove(state, EngineStrength.easy);
          expect(move, isNotNull, reason: 'no move at ply $plies');
          state = GameService.executeMove(state, move!);
          plies++;
        }

        expect(state.isGameOver, isTrue, reason: 'still going after $plies');
        expect(state.winnerId, isNotNull);
        expect(state.playerById(state.winnerId!).hasReachedGoal, isTrue);
      });
    }

    test('it blocks whoever is closest to getting home', () {
      final state = GameStateFactory.createNewGame(playerCount: 3);

      // Seat two is one step away; the others are still at their starts.
      state.playerById(2).moveTo(const Position(7, 4));
      state.currentPlayerId = 1;

      final move = QuoridorEngine.bestMove(state, EngineStrength.hard);

      expect(move, isNotNull);
      expect(
        move!.type,
        MoveType.wallPlace,
        reason: 'let a player walk in rather than walling them',
      );
    });
  });

  group('saving and loading', () {
    test('a four-player game survives a round trip', () {
      final state = GameStateFactory.createNewGame(playerCount: 4);
      state.walls.add(const Wall(Position(3, 3), WallOrientation.vertical));
      state.currentPlayerId = 3;

      final restored = GameState.fromJson(state.toJson());

      expect(restored.playerCount, 4);
      expect(restored.currentPlayerId, 3);
      expect(restored.playerById(3).goal, GoalEdge.right);
      expect(restored.playerById(4).goal, GoalEdge.left);
      expect(restored.walls.length, 1);
    });

    test('a game saved before seats three and four existed still opens', () {
      final legacy = {
        'gameId': 'old',
        'player1': {
          'id': 1,
          'position': {'row': 8, 'col': 4},
          'wallsRemaining': 9,
          'goalRow': 0,
          'name': 'Player 1',
          'isAI': false,
        },
        'player2': {
          'id': 2,
          'position': {'row': 0, 'col': 4},
          'wallsRemaining': 10,
          'goalRow': 8,
          'name': 'AI',
          'isAI': true,
        },
        'walls': <Map<String, dynamic>>[],
        'currentPlayerId': 1,
        'status': 0,
        'createdAt': 0,
        'updatedAt': 0,
        'moveHistory': <Map<String, dynamic>>[],
      };

      final state = GameState.fromJson(legacy);

      expect(state.playerCount, 2);
      expect(state.player1.goal, GoalEdge.top);
      expect(state.player2.goal, GoalEdge.bottom);
      expect(state.player1.wallsRemaining, 9);
    });

    test('the status numbers older builds already store do not move', () {
      expect(GameStatus.playing.index, 0);
      expect(GameStatus.player1Won.index, 1);
      expect(GameStatus.player2Won.index, 2);
      expect(GameStatus.draw.index, 3);
      expect(GameStatus.wonBy(3), GameStatus.player3Won);
      expect(GameStatus.wonBy(4), GameStatus.player4Won);
    });
  });
}
