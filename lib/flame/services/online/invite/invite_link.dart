import 'invite_page.dart';
import '../room_code.dart';

export 'invite_page.dart' show forgetInviteInPage;

/// Links that open the game straight into joining a friend's online game.
///
/// A link is the web build's address with `?join=CODE`, always on [webHome]
/// whichever copy of the game made it, so every invite looks the same and
/// opens the same site. Its QR code joins from any phone camera.
class InviteLink {
  InviteLink._();

  /// Where every invite leads.
  static final Uri webHome = Uri.parse('https://playquoridor.pages.dev/');

  /// Every address the site is served at. An invite link on any of them
  /// opens the installed app; the second is where invites from 1.1.5 and
  /// earlier, and the promo video's QR code, lead.
  static const List<String> hosts = [
    'playquoridor.pages.dev',
    'quoridor-mohager.pages.dev',
  ];

  static const String parameter = 'join';

  /// The link that joins the game with [code].
  static Uri forCode(String code) =>
      webHome.replace(queryParameters: {parameter: code});

  /// The room code [link] carries, or null when it carries none that could
  /// be one.
  static String? codeIn(Uri link) {
    final raw = link.queryParameters[parameter];
    return raw == null ? null : RoomCode.tryParse(raw);
  }

  /// The room code in something scanned from a QR code: an invite link, or
  /// a bare code. Null for anything else.
  static String? codeFromScan(String scanned) {
    final text = scanned.trim();
    final link = Uri.tryParse(text);
    if (link != null && link.hasScheme) return codeIn(link);
    return RoomCode.tryParse(text);
  }

  /// The code in the address this page was opened at, if any.
  static String? fromPage() {
    final page = currentPage();
    return page == null ? null : codeIn(page);
  }
}
