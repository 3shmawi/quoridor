/// What this build is, as stamped in by the release workflows with
/// `--dart-define`.
///
/// The version default must match pubspec.yaml; a test holds them together.
/// The build number and commit default to "unknown" for local builds, which
/// never treat themselves as out of date because of them.
class AppVersion {
  const AppVersion({
    required this.version,
    required this.buildNumber,
    required this.commit,
  });

  static const AppVersion current = AppVersion(
    version: String.fromEnvironment('APP_VERSION', defaultValue: '1.1.2'),
    buildNumber: int.fromEnvironment('BUILD_NUMBER'),
    commit: String.fromEnvironment('APP_COMMIT'),
  );

  /// x.y.z, without the build suffix.
  final String version;

  /// The CI run number; 0 for a local build.
  final int buildNumber;

  /// The git commit; empty for a local build.
  final String commit;
}
