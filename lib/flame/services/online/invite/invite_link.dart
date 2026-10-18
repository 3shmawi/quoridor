import 'invite_page.dart';
import '../room_code.dart';

export 'invite_page.dart' show forgetInviteInPage;

/// Links that open the game straight into joining a friend's online game.
///
/// A link is the web build's address with `?join=CODE`. On the web it points
/// at the site it was opened from, so a GitHub Pages player invites to GitHub
/// Pages; installed apps have no address of their own and use [webHome].
class InviteLink {
  InviteLink._();

  /// Where installed builds send their invites.
  static final Uri webHome = Uri.parse('https://quoridor-mohager.pages.dev/');

  static const String parameter = 'join';

  /// The link that joins the game with [code], on the site at [page], or on
  /// [webHome] when there is no page (an installed app).
  static Uri forCode(String code, {Uri? page}) {
    final home = page ?? currentPage() ?? webHome;
    return Uri(
      scheme: home.scheme,
      host: home.host,
      port: home.hasPort ? home.port : null,
      path: home.path.isEmpty ? '/' : home.path,
      queryParameters: {parameter: code},
    );
  }

  /// The room code [link] carries, or null when it carries none that could
  /// be one.
  static String? codeIn(Uri link) {
    final raw = link.queryParameters[parameter];
    return raw == null ? null : RoomCode.tryParse(raw);
  }

  /// The code in the address this page was opened at, if any.
  static String? fromPage() {
    final page = currentPage();
    return page == null ? null : codeIn(page);
  }
}
