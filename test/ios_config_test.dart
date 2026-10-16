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
}
