/// Hides offensive words in typed chat, in English and Arabic.
///
/// Typed lines go to another person, so the worst words are masked twice:
/// before a line is sent, and again when one is shown, which also covers a
/// line sent from an older build without the filter. Each letter of a masked
/// word becomes a `*`, so the line keeps its shape and nobody wonders whether
/// it was cut short.
///
/// Matching is by whole word, after the spellings people use to slip past a
/// filter are folded away: case, Arabic diacritics and letter variants,
/// stretched letters ("fuuuck") and digits standing in for letters ("sh1t").
class ChatFilter {
  ChatFilter._();

  /// Words masked wherever they appear inside a word ("fucking", "bullshit").
  /// Only roots long and rare enough not to hide innocent words.
  static const List<String> _roots = [
    'fuck',
    'fuk',
    'shit',
    'nigger',
    'nigga',
    'faggot',
    'motherf',
    'bitch',
    'whore',
    'كسمك',
    'كسامك',
    'متناك',
    'شرموط',
    'معرص',
    'منيوك',
    'منيك',
  ];

  /// Words masked only when they are the whole word.
  static const Set<String> _words = {
    'ass',
    'asshole',
    'bastard',
    'dick',
    'dickhead',
    'pussy',
    'slut',
    'fag',
    'retard',
    'cock',
    'wanker',
    'twat',
    'cunt',
    'cunts',
    'كس',
    'كسم',
    'زب',
    'زبي',
    'طيز',
    'عرص',
    'خول',
    'نيك',
    'انيك',
    'هنيك',
    'لبوه',
    'قحبه',
    'شرموطه',
    'متناكه',
  };

  static final RegExp _word = RegExp(r'[\p{L}\p{M}\p{N}@$]+', unicode: true);

  /// [text] with every offensive word masked.
  static String clean(String text) => text.replaceAllMapped(_word, (match) {
    final word = match[0]!;
    return isOffensive(word) ? '*' * word.runes.length : word;
  });

  /// Whether the single word [word] is one to hide.
  static bool isOffensive(String word) {
    final plain = _fold(word);
    if (plain.isEmpty) return false;
    for (final form in {plain, _squeeze(plain)}) {
      if (_words.contains(form)) return true;
      // Arabic glues "و" (and) and "ال" (the) onto the next word.
      for (final prefix in const ['و', 'ال', 'وال', 'يا']) {
        if (form.startsWith(prefix) &&
            _words.contains(form.substring(prefix.length))) {
          return true;
        }
      }
      for (final root in _roots) {
        if (form.contains(root)) return true;
      }
    }
    return false;
  }

  static const Map<String, String> _lookalikes = {
    '0': 'o',
    '1': 'i',
    '3': 'e',
    '4': 'a',
    '5': 's',
    '7': 't',
    '@': 'a',
    r'$': 's',
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ة': 'ه',
    'ى': 'ي',
    'ؤ': 'و',
    'ئ': 'ي',
  };

  /// Lower case, Arabic marks and tatweel dropped, look-alikes unified.
  static String _fold(String word) {
    final out = StringBuffer();
    for (final rune in word.toLowerCase().runes) {
      // Tashkeel, superscript alef and the tatweel stretch.
      if ((rune >= 0x064B && rune <= 0x065F) ||
          rune == 0x0670 ||
          rune == 0x0640) {
        continue;
      }
      final ch = String.fromCharCode(rune);
      out.write(_lookalikes[ch] ?? ch);
    }
    return out.toString();
  }

  /// [word] with each run of one letter cut to a single letter.
  static String _squeeze(String word) {
    final out = StringBuffer();
    int? last;
    for (final rune in word.runes) {
      if (rune != last) out.writeCharCode(rune);
      last = rune;
    }
    return out.toString();
  }
}
