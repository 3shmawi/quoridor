import 'package:flutter/foundation.dart';

/// How a reaction's face moves while it is on screen.
enum ChatMotion {
  /// Hops up and down, tipping side to side: laughing.
  bounce,

  /// Leans slowly one way and the other: thinking it over.
  sway,

  /// Shakes hard from side to side: furious.
  shake,

  /// Trembles on the spot: scared.
  tremble,

  /// Beats like a heart: in love, or blown away.
  pulse,

  /// Drifts up and down, slow as breathing: asleep, or crying.
  float,

  /// Spins round with a hop: celebrating.
  spin,

  /// Rocks from its base like a waving hand.
  wave,

  /// Dips forward and back: a nod.
  nod,
}

/// Everything a player can send in an online game.
///
/// These are the one-tap reactions; players can also type their own words
/// (see [ChatMessage.text]). Each entry is stored by its [name], and
/// `firestore.rules` accepts only these names, so adding one means adding it
/// there too (a test holds the two lists together).
enum QuickChat {
  // Faces: the emoji alone.
  laugh('😂', ChatMotion.bounce),
  cool('😎', ChatMotion.nod),
  thinking('🤔', ChatMotion.sway),
  angry('😡', ChatMotion.shake),
  scared('😱', ChatMotion.tremble),
  crying('😭', ChatMotion.float),
  love('😍', ChatMotion.pulse),
  sleepy('😴', ChatMotion.float),
  mindBlown('🤯', ChatMotion.pulse),
  party('🥳', ChatMotion.spin),
  smirk('😏', ChatMotion.sway),
  hello('👋', ChatMotion.wave),

  // Lines: an emoji with a few words, shown in the reader's language.
  goodLuck('🍀', ChatMotion.spin, isLine: true),
  niceMove('👏', ChatMotion.pulse, isLine: true),
  oops('🙈', ChatMotion.tremble, isLine: true),
  didntMeanIt('😅', ChatMotion.sway, isLine: true),
  misplayed('🤦', ChatMotion.nod, isLine: true),
  hurryUp('⏰', ChatMotion.shake, isLine: true),
  notThatWall('🧱', ChatMotion.nod, isLine: true),
  wellPlayed('🤝', ChatMotion.bounce, isLine: true),
  goodGame('🏆', ChatMotion.spin, isLine: true),
  thanks('🙏', ChatMotion.nod, isLine: true);

  const QuickChat(this.emoji, this.motion, {this.isLine = false});

  final String emoji;
  final ChatMotion motion;

  /// Whether this comes with words, rather than being a face alone.
  final bool isLine;

  static List<QuickChat> get faces =>
      values.where((item) => !item.isLine).toList();

  static List<QuickChat> get lines =>
      values.where((item) => item.isLine).toList();

  /// The entry stored as [name], or null for one this build does not know --
  /// a newer version may have added it.
  static QuickChat? tryParse(Object? name) {
    for (final item in values) {
      if (item.name == name) return item;
    }
    return null;
  }
}

/// One message sent in an online game: a quick reaction, or words the
/// player typed.
@immutable
class ChatMessage {
  /// The longest message a player can type, in characters.
  static const int maxText = 80;

  /// What a typed message is stored as, in place of a reaction's name.
  static const String textCode = 'text';

  /// The document id, chosen by the sender so its own copy and the server's
  /// echo are recognised as the same message.
  final String id;

  /// The seat that sent it.
  final int seat;

  /// The reaction sent, or null for a typed message.
  final QuickChat? item;

  /// The words typed, or null for a reaction.
  final String? text;

  bool get isText => text != null;

  /// When the server took it, or the sender's clock until it has.
  final DateTime? sentAt;

  const ChatMessage({
    required this.id,
    required this.seat,
    this.item,
    this.text,
    this.sentAt,
  }) : assert((item == null) != (text == null), 'a reaction or words');

  /// The same message, dated [sentAt].
  ChatMessage dated(DateTime? sentAt) =>
      ChatMessage(id: id, seat: seat, item: item, text: text, sentAt: sentAt);

  /// [raw] as it is sent: on one line, without spare spaces, and no longer
  /// than [maxText] characters. Empty when there is nothing to send.
  static String tidy(String raw) {
    final line = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final characters = line.runes.toList();
    if (characters.length <= maxText) return line;
    return String.fromCharCodes(characters.take(maxText)).trim();
  }

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.seat == seat &&
      other.item == item &&
      other.text == text &&
      other.sentAt == sentAt;

  @override
  int get hashCode => Object.hash(id, seat, item, text, sentAt);

  @override
  String toString() =>
      'ChatMessage($id, seat $seat, ${item?.name ?? '"$text"'})';
}
