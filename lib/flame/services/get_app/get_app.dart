import '../online/invite/invite_link.dart';

export 'web_device.dart' show currentWebDevice;

/// The kind of device a browser copy of the game is running on, which
/// decides where "Get the app" leads.
enum WebDevice {
  /// iPhone or iPad in Safari, which shows Apple's own app banner.
  iosSafari,

  /// iPhone or iPad in any other browser.
  ios,

  android,

  /// Anything else: a computer, mostly.
  desktop,
}

/// Where each kind of device gets the app.
class GetApp {
  GetApp._();

  static final Uri appStore = Uri.parse(
    'https://apps.apple.com/app/id6752514464',
  );

  static final Uri googlePlay = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.MoRe_H.quoridor',
  );

  /// The page that lists both stores, for a computer.
  static Uri get page => InviteLink.webHome.resolve('get/');

  /// The store [device] installs from, or the page with both.
  static Uri linkFor(WebDevice device) => switch (device) {
    WebDevice.iosSafari || WebDevice.ios => appStore,
    WebDevice.android => googlePlay,
    WebDevice.desktop => page,
  };

  /// Whether to offer the app above the board on [device]: phones only, and
  /// not where Safari already shows Apple's banner for it.
  static bool offersBanner(WebDevice? device) =>
      device == WebDevice.ios || device == WebDevice.android;
}

/// [userAgent] read as a device. An iPad in desktop mode says it is a Mac,
/// but unlike a Mac it has a touch screen.
WebDevice webDeviceFor(String userAgent, {int touchPoints = 0}) {
  final ios =
      RegExp('iPhone|iPad|iPod').hasMatch(userAgent) ||
      (userAgent.contains('Macintosh') && touchPoints > 1);
  if (ios) {
    // Chrome, Firefox, Edge and the in-app browsers all name themselves;
    // only Safari shows the app banner.
    final other = RegExp(
      'CriOS|FxiOS|EdgiOS|OPiOS|GSA/|FBAN|FBAV|Instagram|TikTok|Snapchat|Line/',
    ).hasMatch(userAgent);
    return other || !userAgent.contains('Safari')
        ? WebDevice.ios
        : WebDevice.iosSafari;
  }
  if (userAgent.contains('Android')) return WebDevice.android;
  return WebDevice.desktop;
}
