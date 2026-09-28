import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme.dart';
import 'ai_service.dart';
import 'audio_service.dart';
import 'turn_clock.dart';

/// The player's settings, kept across restarts.
///
/// These used to live only in memory, so the theme, the sound toggle and the
/// difficulty all reset every time the app was closed — the player had to set
/// them again on each launch.
class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const String _darkModeKey = 'settings.darkMode';
  static const String _soundKey = 'settings.sound';
  static const String _validMovesKey = 'settings.showValidMoves';
  static const String _languageKey = 'settings.language';
  static const String _difficultyKey = 'settings.difficulty';
  static const String _turnLimitKey = 'settings.turnLimit';

  /// Languages the game is translated into.
  static const List<Locale> supportedLocales = [Locale('en'), Locale('ar')];

  final ValueNotifier<bool> showValidMoves = ValueNotifier<bool>(true);
  final ValueNotifier<Locale> locale = ValueNotifier<Locale>(
    supportedLocales.first,
  );
  final ValueNotifier<AIDifficulty> difficulty = ValueNotifier<AIDifficulty>(
    AIDifficulty.medium,
  );

  /// How long a player gets per turn.
  ///
  /// Off by default: the game shipped without a clock, and switching one on
  /// under the players already using it would change how their games end
  /// without their asking. It is one tap away in the settings drawer.
  final ValueNotifier<TurnLimit> turnLimit = ValueNotifier<TurnLimit>(
    TurnLimit.off,
  );

  SharedPreferences? _prefs;
  bool _loaded = false;

  /// Reads the stored settings and starts saving any later change.
  ///
  /// Never throws: a device where preferences are unavailable simply gets the
  /// defaults, which is better than refusing to start.
  Future<void> load() async {
    if (_loaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;

      isDarkModeNotifier.value = prefs.getBool(_darkModeKey) ?? true;
      AudioService.instance.enabled.value = prefs.getBool(_soundKey) ?? true;
      showValidMoves.value = prefs.getBool(_validMovesKey) ?? true;
      locale.value = _localeFor(prefs.getString(_languageKey));
      difficulty.value = _difficultyFor(prefs.getString(_difficultyKey));
      turnLimit.value = _turnLimitFor(prefs.getString(_turnLimitKey));
    } catch (error) {
      debugPrint('SettingsService: using defaults, load failed: $error');
    } finally {
      _loaded = true;
      _listen();
    }
  }

  void _listen() {
    isDarkModeNotifier.addListener(
      () => _write(_darkModeKey, isDarkModeNotifier.value),
    );
    AudioService.instance.enabled.addListener(
      () => _write(_soundKey, AudioService.instance.enabled.value),
    );
    showValidMoves.addListener(
      () => _write(_validMovesKey, showValidMoves.value),
    );
    locale.addListener(() => _write(_languageKey, locale.value.languageCode));
    difficulty.addListener(() => _write(_difficultyKey, difficulty.value.name));
    turnLimit.addListener(() => _write(_turnLimitKey, turnLimit.value.name));
  }

  /// Switches between the languages the game supports.
  void toggleLanguage() {
    final index = supportedLocales.indexOf(locale.value);
    locale.value = supportedLocales[(index + 1) % supportedLocales.length];
  }

  bool get isArabic => locale.value.languageCode == 'ar';

  void _write(String key, Object value) {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      if (value is bool) {
        prefs.setBool(key, value);
      } else {
        prefs.setString(key, '$value');
      }
    } catch (error) {
      // A setting that cannot be stored still applies for this session.
      debugPrint('SettingsService: could not store $key: $error');
    }
  }

  static Locale _localeFor(String? code) {
    for (final candidate in supportedLocales) {
      if (candidate.languageCode == code) return candidate;
    }
    return supportedLocales.first;
  }

  static TurnLimit _turnLimitFor(String? name) {
    for (final candidate in TurnLimit.values) {
      if (candidate.name == name) return candidate;
    }
    return TurnLimit.off;
  }

  static AIDifficulty _difficultyFor(String? name) {
    for (final candidate in AIDifficulty.values) {
      if (candidate.name == name) return candidate;
    }
    return AIDifficulty.medium;
  }
}
