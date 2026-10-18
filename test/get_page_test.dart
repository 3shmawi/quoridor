import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the "get the app" page (web/get/index.html), read as plain text.
///
/// The promo QR code opens it: phones are sent to their store to install or
/// update, so a wrong link there sends every scan to the wrong place.
void main() {
  final page = File('web/get/index.html').readAsStringSync();

  test('Android phones go to the app this build publishes', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final appId = RegExp(
      r'applicationId\s*=\s*"([^"]+)"',
    ).firstMatch(gradle)!.group(1)!;
    expect(
      page,
      contains(
        "var PLAY = 'https://play.google.com/store/apps/details?id=$appId'",
      ),
    );
  });

  test('iPhones go to the App Store listing', () {
    expect(
      page,
      contains("var APP_STORE = 'https://apps.apple.com/app/id6752514464'"),
    );
  });

  test('anything else can still play in the browser', () {
    expect(page, contains('href="../"'));
  });

  test('the page reaches the site icons from either address', () {
    // GitHub Pages serves the site under /quoridor/, Cloudflare at the root,
    // so only relative paths work on both.
    expect(page, isNot(contains('href="/')));
    expect(page, isNot(contains('src="/')));
  });
}
