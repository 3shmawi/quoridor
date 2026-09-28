import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/services/app_strings.dart';
import 'package:quoridor/flame/services/settings_service.dart';

void main() {
  const english = AppStrings(Locale('en'));
  const arabic = AppStrings(Locale('ar'));

  group('translation tables', () {
    test('both languages define exactly the same keys', () {
      // A key added to one table and not the other silently falls back to
      // English, which is how half-translated screens happen.
      expect(
        AppStrings.debugArabicKeys.difference(AppStrings.debugEnglishKeys),
        isEmpty,
        reason: 'Arabic has keys English does not',
      );
      expect(
        AppStrings.debugEnglishKeys.difference(AppStrings.debugArabicKeys),
        isEmpty,
        reason: 'English has keys Arabic does not',
      );
    });

    test('no translation is left empty', () {
      for (final table in [AppStrings.debugEnglish, AppStrings.debugArabic]) {
        for (final entry in table.entries) {
          expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        }
      }
    });

    test('placeholders survive translation', () {
      // A %s dropped in translation means a code or a name never appears.
      for (final key in AppStrings.debugEnglishKeys) {
        final en = AppStrings.debugEnglish[key]!;
        final ar = AppStrings.debugArabic[key]!;
        expect(
          '%s'.allMatches(ar).length,
          '%s'.allMatches(en).length,
          reason: '$key: placeholder count differs',
        );
      }
    });
  });

  group('lookup', () {
    test('returns the language asked for', () {
      expect(english.playOnline, 'Play Online');
      expect(arabic.playOnline, isNot('Play Online'));
      expect(arabic.isArabic, isTrue);
      expect(english.isArabic, isFalse);
    });

    test('fills placeholders', () {
      expect(english.nameWins('Alice'), contains('Alice'));
      expect(arabic.nameWins('Alice'), contains('Alice'));
      expect(english.wallsCount(7), contains('7'));
      expect(arabic.wallsCount(7), contains('7'));
    });

    test('a two-placeholder string fills both', () {
      final text = english.codeAndMoves('ABCDEF', 12);
      expect(text, contains('ABCDEF'));
      expect(text, contains('12'));
    });

    test('an unknown locale falls back to English', () {
      const french = AppStrings(Locale('fr'));
      expect(french.playOnline, english.playOnline);
    });
  });

  group('settings', () {
    test('both supported locales are translated', () {
      for (final locale in SettingsService.supportedLocales) {
        expect(AppStrings(locale).appTitle.trim(), isNotEmpty);
      }
    });
  });
}
