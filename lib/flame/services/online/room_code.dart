import 'dart:math';

/// Short codes players read aloud or type to join a friend's game.
///
/// The code has to survive being dictated over a voice call and typed on a
/// phone keyboard, so the alphabet drops the glyphs people confuse: `I`, `L`
/// and `0`. [normalize] folds those back onto the character that is actually
/// generated, which means a player who types `0` for `O`, or `I` for `1`,
/// still joins the right game instead of being told the code is wrong.
class RoomCode {
  RoomCode._();

  /// Characters a generated code may contain. `I`, `L` and `0` are excluded.
  static const String alphabet = 'ABCDEFGHJKMNOPQRSTUVWXYZ123456789';

  /// Number of characters in a code. 33^6 is about 1.3 billion combinations,
  /// far more than enough for codes that live only as long as a game.
  static const int length = 6;

  /// Typed characters folded onto the generated character they resemble.
  static const Map<String, String> _confusions = {'0': 'O', 'I': '1', 'L': '1'};

  static final Random _defaultRandom = Random.secure();

  /// Generates a fresh code.
  static String generate([Random? random]) {
    final rng = random ?? _defaultRandom;
    return List.generate(
      length,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Cleans up something a player typed: trims, uppercases, drops separators
  /// such as spaces and dashes, and folds confusable characters.
  ///
  /// The result is not guaranteed to be a valid code — check with [isValid].
  static String normalize(String input) {
    final buffer = StringBuffer();

    for (final rune in input.toUpperCase().runes) {
      final char = String.fromCharCode(rune);
      final folded = _confusions[char] ?? char;
      if (alphabet.contains(folded)) buffer.write(folded);
    }

    return buffer.toString();
  }

  /// Whether [code] is exactly a well-formed code, with no normalizing.
  static bool isValid(String code) {
    if (code.length != length) return false;
    return code.split('').every(alphabet.contains);
  }

  /// Normalizes [input] and returns it only if it is then a valid code.
  static String? tryParse(String input) {
    final normalized = normalize(input);
    return isValid(normalized) ? normalized : null;
  }
}
