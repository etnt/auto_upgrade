import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_throttle.dart';
import 'version_compare.dart';

/// The update information for a genuinely newer release, handed to the
/// consuming app so it can decide how to notify the user (Option A: open
/// [releasePageUrl] in the browser on approval).
class UpdateInfo {
  /// The release tag with the leading `v` stripped, e.g. `"1.2.0"`.
  final String latestVersion;

  /// The running app's version as passed to the checker.
  final String currentVersion;

  /// The release page URL the app should open with `url_launcher`
  /// (Option A). Falls back to
  /// `https://github.com/{owner}/{repo}/releases/latest` when the API
  /// response carries no `html_url`.
  final String releasePageUrl;

  /// The release body (notes), if any.
  final String? releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releasePageUrl,
    this.releaseNotes,
  });
}

/// The outcome of an update check.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// A newer release exists. The app should prompt the user with [info].
class UpdateAvailable extends UpdateCheckResult {
  final UpdateInfo info;

  const UpdateAvailable(this.info);
}

/// The check ran and the installed version is current.
class UpToDate extends UpdateCheckResult {
  const UpToDate();
}

/// The check was deliberately not performed: the throttle short-circuited it
/// or the version is the `'dev'` sentinel. Distinct from [UpToDate] so
/// tests/UI can tell "checked, nothing to do" from "didn't check".
class CheckSkipped extends UpdateCheckResult {
  const CheckSkipped();
}

/// The check failed (offline, rate-limited, malformed data, ...). Never
/// throws — the checker always resolves with a result.
class CheckError extends UpdateCheckResult {
  final Object cause;

  const CheckError(this.cause);
}

/// Checks a GitHub repository's `/releases/latest` endpoint for a newer
/// version than [currentVersion] and reports the result.
///
/// Never throws: [check] resolves with [UpdateAvailable], [UpToDate],
/// [CheckSkipped], or [CheckError]. The HTTP client and clock are injectable
/// so consumers can test the checker with plain fakes.
class ReleaseChecker {
  final String owner;
  final String repo;
  final String currentVersion;

  final UpdateCheckStore? checkStore;
  final Duration checkInterval;
  final DateTime Function() now;

  final http.Client _client;

  /// Builds below `currentVersion == 'dev'` (local/debug builds) never hit the
  /// network: the sentinel short-circuits to [CheckSkipped].
  static const devVersion = 'dev';

  ReleaseChecker({
    required this.owner,
    required this.repo,
    required this.currentVersion,
    http.Client? httpClient,
    this.checkStore,
    this.checkInterval = const Duration(hours: 24),
    DateTime Function()? now,
  })  : _client = httpClient ?? http.Client(),
        now = now ?? DateTime.now;

  /// The GitHub REST API rejects requests without a `User-Agent` with 403;
  /// because [check] swallows errors as [CheckError], a missing UA would make
  /// updates silently never appear. Always send it.
  static const _acceptHeader = 'application/vnd.github+json';

  Uri get _latestReleaseUrl =>
      Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');

  /// Runs one (possibly skipped) update check.
  Future<UpdateCheckResult> check() async {
    try {
      if (currentVersion == devVersion) return const CheckSkipped();

      // Throttle: a recent successful check short-circuits without HTTP.
      if (checkStore != null) {
        final last = await checkStore!.lastCheckAt();
        if (last != null && now().difference(last) < checkInterval) {
          return const CheckSkipped();
        }
      }

      // A non-`dev` current version that isn't parseable throws inside the
      // try block below and becomes a [CheckError] — never a spurious
      // "update available" or a silent "up to date".
      compareVersions(currentVersion, currentVersion);

      final response = await _client.get(
        _latestReleaseUrl,
        headers: {
          'Accept': _acceptHeader,
          'User-Agent': 'auto_upgrade ($owner/$repo)',
        },
      );
      if (response.statusCode != 200) {
        return CheckError(FormatException(
          'GitHub API returned HTTP ${response.statusCode} '
          'for $_latestReleaseUrl',
        ));
      }

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return CheckError(
            FormatException('Unexpected release payload', response.body));
      }
      final tag = json['tag_name'];
      if (tag is! String) {
        return CheckError(FormatException('Missing tag_name in release'));
      }

      // An unparseable release tag is an error, never silently "older".
      final comparison = compareVersions(tag, currentVersion);

      if (comparison > 0) {
        await _recordChecked();
        return UpdateAvailable(UpdateInfo(
          latestVersion: stripVersionTag(tag),
          currentVersion: currentVersion,
          releasePageUrl:
              (json['html_url'] as String?) ??
                  'https://github.com/$owner/$repo/releases/latest',
          releaseNotes: json['body'] as String?,
        ));
      }

      await _recordChecked();
      return const UpToDate();
    } catch (e) {
      // Errors are swallowed into a result on purpose: an offline or
      // rate-limited check must never crash the app. The throttle is not
      // stamped, so the next launch retries.
      return CheckError(e);
    }
  }

  /// Records a successful check, ignoring storage failures (a failed write
  /// must not turn a successful check into a [CheckError]).
  Future<void> _recordChecked() async {
    try {
      await checkStore?.markChecked(now());
    } catch (_) {}
  }
}
