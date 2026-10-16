import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the iOS bundle ID, read as plain text.
void main() {
  // The App ID registered with Apple. TestFlight failed with "Could not find
  // App with App Identifier 'com.MoReH.quoridor'": Apple's lookup is exact.
  const appId = 'com.moreh.quoridor';

  test('the iOS app builds as the App ID registered with Apple', () {
    final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
        .allMatches(
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        )
        .map((m) => m.group(1)!)
        .toSet();
    expect(ids, {appId, '$appId.RunnerTests'});
  });

  test('fastlane signs and uploads that same App ID', () {
    final fastfile = File('ios/fastlane/Fastfile').readAsStringSync();
    expect(fastfile, contains('APP_ID = "$appId"'));
  });

  test('Firebase is configured for that same iOS app', () {
    final plist = File(
      'ios/Runner/GoogleService-Info.plist',
    ).readAsStringSync();
    String plistValue(String key) => RegExp(
      '<key>$key</key>\\s*<string>([^<]+)</string>',
    ).firstMatch(plist)!.group(1)!;

    final options = File('lib/firebase_options.dart').readAsStringSync();
    final ios = RegExp(
      r'FirebaseOptions ios = FirebaseOptions\(([^)]*)\)',
    ).firstMatch(options)!.group(1)!;

    expect(plistValue('BUNDLE_ID'), appId);
    expect(ios, contains("iosBundleId: '$appId'"));
    expect(ios, contains("appId: '${plistValue('GOOGLE_APP_ID')}'"));
  });
}
