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
/// There is no free text on purpose: a fixed set needs no moderation, reads
/// in either language, and keeps a game about the game. Each entry is stored
/// by its [name], and `firestore.rules` accepts only these names, so adding
/// one means adding it there too (a test holds the two lists together).
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

/// One reaction sent in an online game.
@immutable
class ChatMessage {
  /// The document id, chosen by the sender so its own copy and the server's
  /// echo are recognised as the same message.
  final String id;

  /// The seat that sent it.
  final int seat;

  final QuickChat item;

  /// When the server took it, or the sender's clock until it has.
  final DateTime? sentAt;

  const ChatMessage({
    required this.id,
    required this.seat,
    required this.item,
    this.sentAt,
  });

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.seat == seat &&
      other.item == item &&
      other.sentAt == sentAt;

  @override
  int get hashCode => Object.hash(id, seat, item, sentAt);

  @override
  String toString() => 'ChatMessage($id, seat $seat, ${item.name})';
}
