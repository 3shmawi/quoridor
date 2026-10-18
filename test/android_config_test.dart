import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android build settings, read as plain text.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  int sdk(String name) =>
      int.parse(RegExp('$name\\s*=\\s*(\\d+)').firstMatch(gradle)!.group(1)!);

  // Google Play refused the 1.1.3 bundle ("Target SDK of artifact is too
  // low") once its floor rose to API 36 on 31 August 2026.
  test('the app targets an SDK Google Play still accepts', () {
    expect(sdk('targetSdk'), greaterThanOrEqualTo(36));
  });

  test('the app compiles against the SDK it targets', () {
    expect(sdk('compileSdk'), greaterThanOrEqualTo(sdk('targetSdk')));
  });

  // The QR scanner (mobile_scanner) brings CameraX 1.6, whose libraries
  // refuse to build with an Android Gradle plugin older than 8.9.1; CI's
  // Android build failed on 8.7.3.
  test('the Android Gradle plugin is new enough for the QR scanner', () {
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final version = RegExp(
      r'id\("com\.android\.application"\) version "(\d+)\.(\d+)\.(\d+)"',
    ).firstMatch(settings)!;
    final parts = [for (var i = 1; i <= 3; i++) int.parse(version.group(i)!)];
    expect(
      parts[0] * 10000 + parts[1] * 100 + parts[2],
      greaterThanOrEqualTo(80901),
      reason: 'AGP ${parts.join('.')}',
    );
  });

  // AGP 8.9 needs Gradle 8.11.1 or newer; the wrapper is on 8.12.
  test('Gradle is new enough for that plugin', () {
    final wrapper = File(
      'android/gradle/wrapper/gradle-wrapper.properties',
    ).readAsStringSync();
    final version = RegExp(r'gradle-(\d+)\.(\d+)').firstMatch(wrapper)!;
    final major = int.parse(version.group(1)!);
    final minor = int.parse(version.group(2)!);
    expect(major > 8 || (major == 8 && minor >= 12), isTrue);
  });
}
