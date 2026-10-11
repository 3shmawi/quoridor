import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuoridorGame game;

  setUp(() async {
    game = QuoridorGame();
    await game.onLoad();
    // Seat 1 is to move, and this device holds seat 1.
    game.localPlayerId = 1;
  });

  test('the seat to move may act when the server agrees', () {
    game.turnGate = () => true;
    expect(game.canActNow, isTrue);
  });

  test('the board stays still while the server says it is not our turn', () {
    // The case the seat check alone misses: the game is still waiting for
    // players, or a move is on its way, so the board's own turn says seat 1
    // while the server does not.
    game.turnGate = () => false;
    expect(game.canActNow, isFalse);
  });

  test('another seat cannot act whatever the gate says', () {
    game.localPlayerId = 2;
    game.turnGate = () => true;
    expect(game.canActNow, isFalse);
  });
}
