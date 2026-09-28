import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/services/turn_clock.dart';

void main() {
  late DateTime now;
  late TurnClock clock;
  late int expiries;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    expiries = 0;
    clock = TurnClock(now: () => now)
      ..limit = TurnLimit.thirtySeconds
      ..onExpired = () => expiries++;
  });

  tearDown(() => clock.dispose());

  void advance(Duration by) {
    now = now.add(by);
    clock.tick();
  }

  test('a turn starts with the whole limit on the clock', () {
    clock.beginTurn('turn-1');
    expect(clock.remaining.value, const Duration(seconds: 30));
  });

  test('time runs down as the turn goes on', () {
    clock.beginTurn('turn-1');
    advance(const Duration(seconds: 11));
    expect(clock.remaining.value, const Duration(seconds: 19));
  });

  test('handing over the same turn again does not restart it', () {
    clock.beginTurn('turn-1');
    advance(const Duration(seconds: 11));

    // This is what a rebuild looks like: the same turn, offered repeatedly.
    clock.beginTurn('turn-1');
    expect(clock.remaining.value, const Duration(seconds: 19));
  });

  test('a new turn gets a full clock', () {
    clock.beginTurn('turn-1');
    advance(const Duration(seconds: 11));

    clock.beginTurn('turn-2');
    expect(clock.remaining.value, const Duration(seconds: 30));
  });

  test('running out fires once, not on every later tick', () {
    clock.beginTurn('turn-1');
    advance(const Duration(seconds: 30));
    expect(expiries, 1);
    expect(clock.remaining.value, Duration.zero);

    advance(const Duration(seconds: 5));
    advance(const Duration(seconds: 5));
    expect(expiries, 1);
  });

  test('a turn that never ran out never fires', () {
    clock.beginTurn('turn-1');
    advance(const Duration(seconds: 29));
    clock.beginTurn('turn-2');
    advance(const Duration(seconds: 29));
    expect(expiries, 0);
  });

  test('stopping leaves nothing on the clock', () {
    clock.beginTurn('turn-1');
    clock.stop();

    expect(clock.remaining.value, isNull);
    expect(clock.isRunning, isFalse);

    advance(const Duration(seconds: 60));
    expect(expiries, 0);
  });

  test('a stopped turn can be started again', () {
    clock.beginTurn('turn-1');
    clock.stop();
    clock.beginTurn('turn-1');
    expect(clock.remaining.value, const Duration(seconds: 30));
  });

  group('when the limit is off', () {
    setUp(() => clock.limit = TurnLimit.off);

    test('no turn is timed', () {
      clock.beginTurn('turn-1');
      expect(clock.remaining.value, isNull);
      expect(clock.isRunning, isFalse);
    });

    test('nothing ever runs out', () {
      clock.beginTurn('turn-1');
      advance(const Duration(minutes: 10));
      expect(expiries, 0);
    });
  });

  test('changing the limit mid-turn restarts the turn on the new one', () {
    clock.beginTurn('turn-1');
    advance(const Duration(seconds: 25));

    clock.limit = TurnLimit.sixtySeconds;

    // Not the five seconds that were left, and not five seconds scaled up:
    // the player chose a minute, so they get a minute.
    expect(clock.remaining.value, const Duration(seconds: 60));
  });

  test('turning the limit off mid-turn clears the clock', () {
    clock.beginTurn('turn-1');
    clock.limit = TurnLimit.off;

    expect(clock.remaining.value, isNull);
    advance(const Duration(minutes: 5));
    expect(expiries, 0);
  });

  test('every limit but off has a duration matching its name', () {
    expect(TurnLimit.off.duration, isNull);
    expect(TurnLimit.fifteenSeconds.seconds, 15);
    expect(TurnLimit.thirtySeconds.seconds, 30);
    expect(TurnLimit.sixtySeconds.seconds, 60);
  });

  test('a late tick reports the real time left, not a missed count', () {
    clock.beginTurn('turn-1');

    // A phone that slept through most of the turn: one tick, 20 seconds on.
    advance(const Duration(seconds: 20));
    expect(clock.remaining.value, const Duration(seconds: 10));
  });
}
