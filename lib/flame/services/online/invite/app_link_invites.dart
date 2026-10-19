import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'invite_link.dart';

/// Invite links that open the installed app, as room codes.
///
/// Android App Links and iOS Universal Links hand the app the invite link a
/// friend shared ([InviteLink.forCode]) instead of opening it in a browser.
/// [first] is the link the app was started from, if any; [later] carries the
/// ones that arrive while it is already running.
class AppLinkInvites {
  const AppLinkInvites({this.first, this.later = const Stream.empty()});

  final String? first;
  final Stream<String> later;

  /// Reads the links this platform hands the app. On the web the page
  /// address is the link, and nothing arrives later.
  static Future<AppLinkInvites> start() async {
    if (kIsWeb) return AppLinkInvites(first: InviteLink.fromPage());
    final links = AppLinks();
    return from(initial: links.getInitialLink, links: links.uriLinkStream);
  }

  /// Splits [links] into the link the app was opened from and later ones.
  ///
  /// The stream repeats the opening link to its first listener, so that one
  /// copy is skipped: the app would otherwise try to join the same game twice.
  /// Links that carry no room code (the site's other pages) are ignored.
  @visibleForTesting
  static Future<AppLinkInvites> from({
    required Future<Uri?> Function() initial,
    required Stream<Uri> links,
  }) async {
    Uri? opening;
    try {
      opening = await initial().timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('AppLinkInvites: no initial link: $error');
    }
    var echo = opening;
    final later = links
        .where((link) {
          final repeat = echo != null && link == echo;
          echo = null;
          return !repeat;
        })
        .map(InviteLink.codeIn)
        .where((code) => code != null)
        .cast<String>();
    return AppLinkInvites(
      first: opening == null ? null : InviteLink.codeIn(opening),
      later: later,
    );
  }
}
