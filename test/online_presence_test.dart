import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';

/// Mirrors the staleness rule the controller applies, so the threshold itself
/// is pinned by a test rather than only living inside a private method.
bool isAway(DateTime? lastSeen, {DateTime? now}) {
  if (lastSeen == null) return true;
  final reference = now ?? DateTime.now();
  return reference.difference(lastSeen) > OnlineGameController.presenceTimeout;
}

void main() {
  group('presence thresholds', () {
    test('the timeout allows at least three missed heartbeats', () {
      // A single slow round trip must not raise a false "opponent away".
      expect(
        OnlineGameController.presenceTimeout,
        greaterThan(OnlineGameController.heartbeatInterval * 3),
      );
    });

    test('a player who never reported in counts as away', () {
      expect(isAway(null), isTrue);
    });

    test('a fresh heartbeat counts as present', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      expect(
        isAway(now.subtract(const Duration(seconds: 2)), now: now),
        isFalse,
      );
    });

    test('a heartbeat inside the window still counts as present', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final justInside = now.subtract(
        OnlineGameController.presenceTimeout - const Duration(seconds: 1),
      );
      expect(isAway(justInside, now: now), isFalse);
    });

    test('a heartbeat past the window counts as away', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final justOutside = now.subtract(
        OnlineGameController.presenceTimeout + const Duration(seconds: 1),
      );
      expect(isAway(justOutside, now: now), isTrue);
    });
  });

  group('connection states', () {
    test('every state is distinct and named', () {
      final names = OnlineConnectionState.values.map((s) => s.name).toSet();
      expect(names.length, OnlineConnectionState.values.length);
    });
  });

  group('session drives what the banner can say', () {
    const alice = OnlinePlayer(uid: 'uid-alice', displayName: 'Alice');
    const bob = OnlinePlayer(uid: 'uid-bob', displayName: 'Bob');

    OnlineGame game({
      OnlineGameStatus status = OnlineGameStatus.active,
      Map<int, OnlinePlayer>? players,
    }) => OnlineGame(
      gameId: 'g1',
      roomCode: 'ABCDEF',
      status: status,
      players: players ?? const {1: alice, 2: bob},
      currentPlayerId: 1,
      moveCount: 0,
      board: GameStateFactory.createNewGame(player2IsAI: false),
    );

    test('a game with one seat is waiting, not live', () {
      final waiting = game(
        status: OnlineGameStatus.waiting,
        players: const {1: alice},
      );
      expect(waiting.hasBothPlayers, isFalse);
      expect(
        OnlineSession.forUid(waiting, 'uid-alice').isLocalTurn,
        isFalse,
        reason: 'nobody may move before the opponent arrives',
      );
    });

    test('the opponent name the banner shows is the other seat', () {
      final session = OnlineSession.forUid(game(), 'uid-bob');
      expect(session.opponent?.displayName, 'Alice');
    });

    test('a finished game is over for both players', () {
      final finished = game(status: OnlineGameStatus.finished);
      expect(finished.isOver, isTrue);
      expect(OnlineSession.forUid(finished, 'uid-alice').isLocalTurn, isFalse);
      expect(OnlineSession.forUid(finished, 'uid-bob').isLocalTurn, isFalse);
    });
  });
}
