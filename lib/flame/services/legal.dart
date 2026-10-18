import 'online/invite/invite_link.dart';

/// Pages the stores require the app to link to.
class Legal {
  Legal._();

  /// What the game stores and how to have it deleted (web/privacy/).
  static final Uri privacyPolicy = InviteLink.webHome.resolve('privacy/');
}
