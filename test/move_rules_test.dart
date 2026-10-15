import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/game_service.dart';

void main() {
  GameState fresh() =>
      GameStateFactory.createNewGame(gameId: 'g', player2IsAI: false);

  test('playing a move leaves the state it was played on untouched', () {
    final before = fresh();
    final after = GameService.executeMove(
      before,
      const GameMove.pawnMove(Position(7, 4), 1),
    );

    expect(after.player1.position, const Position(7, 4));
    expect(before.player1.position, GameConstants.player1Start);

    GameService.executeMove(
      after,
      const GameMove.wallPlace(
        Wall(Position(4, 3), WallOrientation.horizontal),
        2,
      ),
    );
    expect(after.player2.wallsRemaining, GameConstants.maxWallsPerPlayer);
  });

  test('a move for the seat not on turn is refused', () {
    // Seat 2 stepping forward is a fine move on its own pieces, but it is
    // seat 1's turn -- and executing it used to move seat 1's pawn instead.
    const move = GameMove.pawnMove(Position(1, 4), 2);
    expect(GameService.isValidMove(fresh(), move), isFalse);
    expect(() => GameService.executeMove(fresh(), move), throwsArgumentError);
  });

  test('nothing is legal once the game is over', () {
    final state = fresh()..status = GameStatus.player2Won;
    expect(
      GameService.isValidMove(
        state,
        const GameMove.pawnMove(Position(7, 4), 1),
      ),
      isFalse,
    );
  });
}
