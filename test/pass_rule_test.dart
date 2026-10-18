import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/player.dart';
import 'package:quoridor/flame/services/ai/quoridor_engine.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/game_service.dart';

/// Player 1 in the bottom-left corner, walled off from (8, 1), with players
/// 2 and 3 stacked above: no step, no jump, no slipping round. Out of walls,
/// player 1 has nothing to play.
GameState boxedIn({int wallsLeft = 0, bool seat1IsAI = false}) => GameState(
  gameId: 'boxed',
  players: [
    PlayerFactory.seat(1, playerCount: 4, isAI: seat1IsAI)
      ..position = const Position(8, 0)
      ..wallsRemaining = wallsLeft,
    PlayerFactory.seat(2, playerCount: 4)..position = const Position(7, 0),
    PlayerFactory.seat(3, playerCount: 4)..position = const Position(6, 0),
    PlayerFactory.seat(4, playerCount: 4),
  ],
  walls: [const Wall(Position(7, 1), WallOrientation.vertical)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the rule', () {
    test('a boxed-in player with no walls must pass', () {
      final state = boxedIn();
      expect(state.getValidMoves(state.currentPlayer.position), isEmpty);
      expect(GameService.mustPass(state), isTrue);
      expect(GameService.isValidMove(state, const GameMove.pass(1)), isTrue);
      expect(GameService.getValidMoves(state), [const GameMove.pass(1)]);
    });

    test('passing hands the turn on and changes nothing else', () {
      final after = GameService.executeMove(boxedIn(), const GameMove.pass(1));
      expect(after.currentPlayerId, 2);
      expect(after.player1.position, const Position(8, 0));
      expect(after.walls, hasLength(1));
      expect(after.moveHistory.single, const GameMove.pass(1));
    });

    test('a wall in hand is a move, so passing is not allowed', () {
      final state = boxedIn(wallsLeft: 3);
      expect(GameService.mustPass(state), isFalse);
      expect(GameService.isValidMove(state, const GameMove.pass(1)), isFalse);
    });

    test('a player who can step may not pass', () {
      final state = GameStateFactory.createNewGame(player2IsAI: false);
      expect(GameService.isValidMove(state, const GameMove.pass(1)), isFalse);
    });

    test('a pass survives a round trip through JSON', () {
      const move = GameMove.pass(3);
      expect(GameMove.fromJson(move.toJson()), move);

      final after = GameService.executeMove(boxedIn(), const GameMove.pass(1));
      final decoded = GameState.fromJson(after.toJson());
      expect(decoded.moveHistory.single.type, MoveType.pass);
    });
  });

  group('playing it', () {
    setUp(() => AIService.search = AIService.searchInline);

    test('a pass is allowed for a turn that ran out, and not otherwise', () {
      final start = GameStateFactory.createNewGame(player2IsAI: false);
      const pass = GameMove.pass(1);
      expect(GameService.isValidMove(start, pass), isFalse);
      expect(GameService.isValidMove(start, pass, timedOut: true), isTrue);
      // Only for the player whose turn it is.
      expect(
        GameService.isValidMove(start, const GameMove.pass(2), timedOut: true),
        isFalse,
      );
    });

    test('the computer passes when it has to', () {
      final move = QuoridorEngine.bestMove(
        boxedIn(seat1IsAI: true),
        EngineStrength.medium,
      );
      expect(move, const GameMove.pass(1));
    });

    testWidgets('a stuck player\'s turn passes by itself, and says so', (
      tester,
    ) async {
      final game = QuoridorGame();
      await game.onLoad();
      final passed = <int>[];
      game.onTurnPassed = passed.add;

      game.updateGameState(boxedIn());
      expect(game.gameState.currentPlayerId, 1);

      await tester.pump(QuoridorGame.forcedPassDelay);
      await tester.pump();

      expect(game.gameState.currentPlayerId, 2);
      expect(passed, [1]);
    });

    testWidgets('a player who can move is never passed for', (tester) async {
      final game = QuoridorGame();
      await game.onLoad();
      game.updateGameState(boxedIn(wallsLeft: 1));

      await tester.pump(QuoridorGame.forcedPassDelay * 2);
      expect(game.gameState.currentPlayerId, 1);
      expect(game.gameState.moveHistory, isEmpty);
    });
  });
}
