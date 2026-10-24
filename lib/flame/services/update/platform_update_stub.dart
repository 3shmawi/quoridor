import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../get_app/get_app.dart';
import 'update_checker.dart';

/// Where installed builds read the newest release. `releases/latest` only
/// ever points at a finished release, so this never names a build that is
/// still being made.
final Uri latestJsonUrl = Uri.parse(
  'https://github.com/3shmawi/quoridor/releases/latest/download/latest.json',
);

final Uri _releasePage = Uri.parse(
  'https://github.com/3shmawi/quoridor/releases/latest',
);

/// Phones update through their store; the desktop builds come from GitHub
/// Releases.
UpdateRoute get platformRoute => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => UpdateRoute.store,
  _ => UpdateRoute.download,
};

StoreLookup? get storeLookup => switch (defaultTargetPlatform) {
  TargetPlatform.android => _googlePlay,
  TargetPlatform.iOS => _appStore,
  _ => null,
};

Future<void> applyUpdate(UpdateRoute route) async {
  final url = route != UpdateRoute.store
      ? _releasePage
      : defaultTargetPlatform == TargetPlatform.iOS
      ? GetApp.appStore
      : GetApp.googlePlay;
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Google Play says whether it has a newer build for this install. A copy
/// installed from GitHub Releases (or from a computer) is not Play's to
/// update, and is sent back to GitHub.
Future<StoreRelease?> _googlePlay() async {
  final package = await PackageInfo.fromPlatform();
  if (package.installerStore != 'com.android.vending') {
    throw const NotFromStore();
  }
  final update = await InAppUpdate.checkForUpdate();
  if (update.updateAvailability != UpdateAvailability.updateAvailable) {
    return null;
  }
  return StoreRelease(buildNumber: update.availableVersionCode);
}

/// Apple's public lookup names the version the App Store offers. It is
/// asked in the player's own country first, where the app may be listed
/// when it is not in the default (US) store.
Future<StoreRelease?> _appStore() async {
  final package = await PackageInfo.fromPlatform();
  final country = PlatformDispatcher.instance.locale.countryCode;
  for (final store in [?country?.toLowerCase(), null]) {
    final url = Uri.https('itunes.apple.com', '/lookup', {
      'bundleId': package.packageName,
      'country': ?store,
    });
    final response = await http.get(url);
    if (response.statusCode != 200) continue;
    final release = parseAppStoreLookup(response.body);
    if (release != null) return release;
  }
  return null;
}
