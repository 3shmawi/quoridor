import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/services/online/room_code.dart';

void main() {
  group('generation', () {
    test('produces a code of the documented length', () {
      expect(RoomCode.generate().length, RoomCode.length);
    });

    test('only ever uses the unambiguous alphabet', () {
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        for (final char in RoomCode.generate(random).split('')) {
          expect(
            RoomCode.alphabet.contains(char),
            isTrue,
            reason: '$char is not in the room code alphabet',
          );
        }
      }
    });

    test('never emits the glyphs people confuse', () {
      final random = Random(11);
      for (var i = 0; i < 500; i++) {
        expect(RoomCode.generate(random), isNot(matches(RegExp('[IL0]'))));
      }
    });

    test('does not keep returning the same code', () {
      final codes = {for (var i = 0; i < 50; i++) RoomCode.generate()};
      expect(codes.length, greaterThan(1));
    });
  });

  group('normalize', () {
    test('uppercases', () {
      expect(RoomCode.normalize('abcdef'), 'ABCDEF');
    });

    test('drops spaces, dashes and other separators', () {
      expect(RoomCode.normalize(' AB-CD EF '), 'ABCDEF');
      expect(RoomCode.normalize('AB_CD.EF'), 'ABCDEF');
    });

    test('folds a typed zero onto the letter O', () {
      expect(RoomCode.normalize('A0CDEF'), 'AOCDEF');
    });

    test('folds typed I and L onto the digit 1', () {
      expect(RoomCode.normalize('AICDEF'), 'A1CDEF');
      expect(RoomCode.normalize('ALCDEF'), 'A1CDEF');
    });

    test('is idempotent', () {
      const messy = 'a0-i l';
      expect(
        RoomCode.normalize(RoomCode.normalize(messy)),
        RoomCode.normalize(messy),
      );
    });

    test('leaves a generated code untouched', () {
      final random = Random(3);
      for (var i = 0; i < 200; i++) {
        final code = RoomCode.generate(random);
        expect(RoomCode.normalize(code), code);
      }
    });
  });

  group('validation', () {
    test('accepts a generated code', () {
      expect(RoomCode.isValid(RoomCode.generate()), isTrue);
    });

    test('rejects the wrong length', () {
      expect(RoomCode.isValid('ABCDE'), isFalse);
      expect(RoomCode.isValid('ABCDEFG'), isFalse);
    });

    test('rejects excluded characters without normalizing', () {
      expect(RoomCode.isValid('ABCDE0'), isFalse);
      expect(RoomCode.isValid('ABCDEI'), isFalse);
    });

    test('tryParse recovers a mistyped code', () {
      // A player reading "AOCDEF" aloud may well type a zero.
      expect(RoomCode.tryParse('a0-cdef'), 'AOCDEF');
    });

    test('tryParse returns null when nothing valid is left', () {
      expect(RoomCode.tryParse('!!!'), isNull);
      expect(RoomCode.tryParse('ABC'), isNull);
    });
  });
}
