import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/move_notation.dart';

void main() {
  test('squares are lettered from the left and numbered from player 1', () {
    expect(MoveNotation.square(GameConstants.player1Start), 'e1');
    expect(MoveNotation.square(GameConstants.player2Start), 'e9');
    expect(MoveNotation.square(const Position(8, 0)), 'a1');
    expect(MoveNotation.square(const Position(0, 8)), 'i9');
  });

  test('walls are named by the top-left square of their block', () {
    // Between ranks 2 and 3 across e and f; rank 3 is the top of the block.
    expect(
      MoveNotation.wall(const Wall(Position(7, 4), WallOrientation.horizontal)),
      'e3h',
    );
    // Between columns d and e, down rows 5 and 4.
    expect(
      MoveNotation.wall(const Wall(Position(4, 4), WallOrientation.vertical)),
      'd5v',
    );
  });

  test('a move reads as its square or wall, and a pass as nothing', () {
    expect(MoveNotation.of(const GameMove.pawnMove(Position(7, 4), 1)), 'e2');
    expect(
      MoveNotation.of(
        const GameMove.wallPlace(
          Wall(Position(1, 0), WallOrientation.horizontal),
          2,
        ),
      ),
      'a9h',
    );
    expect(MoveNotation.of(const GameMove.pass(3)), isNull);
  });
}
