import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/pages/game_page.dart';
import 'package:quoridor/flame/services/identity_service.dart';

/// Where [edge] ends up after the board is turned [turns] quarter turns
/// clockwise.
GoalEdge turned(GoalEdge edge, int turns) {
  const clockwise = [
    GoalEdge.top,
    GoalEdge.right,
    GoalEdge.bottom,
    GoalEdge.left,
  ];
  return clockwise[(clockwise.indexOf(edge) + turns) % 4];
}

void main() {
  test(
    'every seat sees its own goal at the top, so it starts at the bottom',
    () {
      for (var seat = 1; seat <= 4; seat++) {
        expect(
          turned(GoalEdge.goalOfSeat(seat), viewTurnsForSeat(seat)),
          GoalEdge.top,
          reason: 'seat $seat',
        );
      }
    },
  );

  test('a shared device is not turned', () {
    expect(viewTurnsForSeat(null), 0);
  });

  test(
    'an empty or overlong name is refused before anything is sent',
    () async {
      expect(await IdentityService.instance.setDisplayName('   '), isFalse);
      expect(await IdentityService.instance.setDisplayName('x' * 21), isFalse);
    },
  );
}
