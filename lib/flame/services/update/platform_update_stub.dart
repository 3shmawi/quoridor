import 'package:url_launcher/url_launcher.dart';

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

const UpdateRoute platformRoute = UpdateRoute.download;

Future<void> applyUpdate() async {
  await launchUrl(_releasePage, mode: LaunchMode.externalApplication);
}
