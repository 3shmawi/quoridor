import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/game_service.dart';

/// Boards from real games, for the Security Rules suite to replay.
///
/// The rules check what a move may do to the board, so they have to agree
/// with what [GameService] actually writes, field for field. The rules suite
/// (test/rules) replays these as the client would; this test keeps the file
/// in step with the code. After a deliberate change to the board format, run
/// it once with UPDATE_RULES_FIXTURES=1 and commit the result.
void main() {
  test('the rules fixtures match what the game writes', () {
    final fixture = {
      // Seat 1 walks up column e while seat 2 spends walls on the a-b side,
      // then wins by stepping diagonally round seat 2's pawn.
      'twoPlayers': _replay(
        GameStateFactory.createNewGame(
          gameId: 'fixture-2',
          player1Name: 'Alice',
          player2Name: 'Bob',
          player2IsAI: false,
        ),
        [
          for (var row = 7; row >= 1; row--) ...[
            GameMove.pawnMove(Position(row, 4), 1),
            GameMove.wallPlace(
              Wall(Position(8 - row, 0), WallOrientation.horizontal),
              2,
            ),
          ],
          const GameMove.pawnMove(Position(0, 3), 1),
        ],
      ),
      // One round at a table of three, so the turn wraps back to seat 1.
      'threePlayers': _replay(
        GameStateFactory.createNewGame(
          gameId: 'fixture-3',
          player2IsAI: false,
          playerCount: 3,
        ),
        const [
          GameMove.pawnMove(Position(7, 4), 1),
          GameMove.wallPlace(
            Wall(Position(4, 3), WallOrientation.horizontal),
            2,
          ),
          GameMove.pawnMove(Position(4, 1), 3),
        ],
      ),
    };

    final encoded = '${const JsonEncoder.withIndent('  ').convert(fixture)}\n';
    final file = File('test/rules/fixtures/real_games.json');
    if (Platform.environment['UPDATE_RULES_FIXTURES'] == '1') {
      file.writeAsStringSync(encoded);
    }
    expect(file.readAsStringSync(), encoded);
  });
}

/// Every board from [start] through [moves], each read back from JSON before
/// the next move, the way the online client decodes the stored board.
List<Map<String, dynamic>> _replay(GameState start, List<GameMove> moves) {
  var state = _roundTrip(start);
  final boards = [_stable(state)];
  for (final move in moves) {
    state = _roundTrip(GameService.executeMove(state, move));
    boards.add(_stable(state));
  }
  expect(state.isGameOver || moves.length == 3, isTrue);
  return boards;
}

GameState _roundTrip(GameState state) => GameState.fromJson(
  jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
);

/// The board as stored, with its clock readings pinned so the file is
/// stable. The rules never look at them.
Map<String, dynamic> _stable(GameState state) => state.toJson()
  ..['createdAt'] = 0
  ..['updatedAt'] = 0;
