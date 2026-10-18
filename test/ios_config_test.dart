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

  test('the app says why it asks for the camera', () {
    // iOS ends an app that opens the camera without saying why, and App
    // Review refuses one. The camera scans invite QR codes.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      RegExp(
        r'<key>NSCameraUsageDescription</key>\s*<string>[^<]+</string>',
      ).hasMatch(plist),
      isTrue,
    );
  });

  test('the app targets iOS 15.0 or later everywhere', () {
    // App Store Connect warns (90068) that from April 2027 it refuses apps
    // targeting less. Every place the minimum is set has to agree.
    double at(String text, RegExp pattern) =>
        double.parse(pattern.firstMatch(text)!.group(1)!);

    final podfile = File('ios/Podfile').readAsStringSync();
    expect(
      at(podfile, RegExp(r"^platform :ios, '([\d.]+)'", multiLine: true)),
      greaterThanOrEqualTo(15.0),
    );
    expect(
      podfile,
      contains("config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'"),
    );

    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);',
    ).allMatches(project).map((m) => double.parse(m.group(1)!)).toList();
    expect(targets, isNotEmpty);
    expect(targets, everyElement(greaterThanOrEqualTo(15.0)));

    final framework = File(
      'ios/Flutter/AppFrameworkInfo.plist',
    ).readAsStringSync();
    expect(
      at(
        framework,
        RegExp(r'<key>MinimumOSVersion</key>\s*<string>([\d.]+)</string>'),
      ),
      greaterThanOrEqualTo(15.0),
    );
  });
}
