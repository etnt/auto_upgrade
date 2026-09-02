/// `auto_upgrade` — check a GitHub repository's Releases for a newer version
/// of the running Flutter app.
///
/// The package is headless by design (Option A — notify and open): it reports
/// *that* an update exists and *where*; the consuming app decides how to ask
/// the user and opens the release page (e.g. with `url_launcher`). No APK
/// download, no install permission, no UI in the package.
///
/// Minimal wiring in a consuming app (~15 lines, see the package README):
///
/// ```dart
/// final checker = ReleaseChecker(
///   owner: 'your-org',
///   repo: 'your-app',
///   currentVersion: appVersion,
///   checkStore: SharedPrefsUpdateCheckStore(prefs),
/// );
///
/// final result = await checker.check();
/// if (result is UpdateAvailable) {
///   // Show a dialog; on approval:
///   launchUrl(Uri.parse(result.info.releasePageUrl),
///       mode: LaunchMode.externalApplication);
/// }
/// ```
library;

export 'src/release_check.dart';
export 'src/shared_prefs_store.dart';
export 'src/update_throttle.dart';
export 'src/version_compare.dart';
