import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/board_component.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';

void main() {
  late BoardComponent board;
  late GameState state;

  setUp(() {
    state = GameStateFactory.createNewGame();
    board = BoardComponent(state)..size = Vector2(400, 400);

    // The board lays itself out on its first tap, which is what a real frame
    // would have done before any of this. Put back down what that tap picked up.
    board.handleTap(Vector2.zero());
    board.clearInteraction();
  });

  /// The centre of the square [position] sits on.
  Vector2 centreOf(Position position) {
    final centre = board.metrics.cellCenter(position);
    return Vector2(centre.dx, centre.dy);
  }

  group('when the board may be used', () {
    test('tapping your own pawn picks it up', () {
      board.handleTap(centreOf(state.currentPlayer.position));
      expect(board.selectedPawn, state.currentPlayer.position);
    });

    test('tapping elsewhere lines a wall up', () {
      board.handleTap(Vector2(120, 120));
      expect(board.pendingWall, isNotNull);
    });
  });

  group('when it is not this device\'s turn', () {
    setUp(() => board.canInteract = () => false);

    test('tapping your own pawn does not pick it up', () {
      board.handleTap(centreOf(state.currentPlayer.position));
      expect(board.selectedPawn, isNull);
    });

    test('tapping elsewhere previews no wall', () {
      board.handleTap(Vector2(120, 120));
      expect(board.pendingWall, isNull);
    });

    test('hovering previews no wall', () {
      board.handleHover(Vector2(120, 120));
      expect(board.pendingWall, isNull);
    });

    test('a wall lined up before the turn passed is put back down', () {
      board.canInteract = () => true;
      board.handleTap(Vector2(120, 120));
      expect(board.pendingWall, isNotNull);

      board.canInteract = () => false;
      board.handleHover(Vector2(150, 150));
      expect(board.pendingWall, isNull);
    });
  });
}
