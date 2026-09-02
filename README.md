# auto_upgrade

A standalone, reusable Flutter package that checks a GitHub repository's
Releases for a newer version of the running app and reports the result.

It is **headless by design** (Option A — notify and open): the package tells
you *that* an update exists and *where*; your app decides how to ask the user
and opens the release page in the browser (e.g. via `url_launcher`). No APK
download, no install permission, no UI in the package.

## Adding it to your app

```yaml
dependencies:
  auto_upgrade:
    git:
      url: https://github.com/etnt/auto_upgrade.git
```

You also need `url_launcher` in the app for the open-the-release-page step,
and an Android `<queries>` entry so Android 11+ can see a browser (see
[Android note](#android-note) below).

## Usage (~15 lines)

```dart
import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final checker = ReleaseChecker(
    owner: 'your-org',
    repo: 'your-app',
    // Version injected at build time, e.g. --dart-define=APP_VERSION=1.2.0.
    // The literal 'dev' short-circuits the check (local builds never query).
    currentVersion: const String.fromEnvironment(
      'APP_VERSION',
      defaultValue: 'dev',
    ),
    // Persists the last successful check so the app queries GitHub at most
    // once per interval (default: 24 h). Omit to check on every launch.
    checkStore: SharedPrefsUpdateCheckStore(prefs),
  );

  final result = await checker.check(); // Never throws.
  if (result is UpdateAvailable) {
    // Show your own dialog; on the user's approval:
    // launchUrl(Uri.parse(result.info.releasePageUrl),
    //     mode: LaunchMode.externalApplication);
  }
}
```

## The result types

| Result            | Meaning                                                        |
| ----------------- | -------------------------------------------------------------- |
| `UpdateAvailable` | A genuinely newer release exists; carries an `UpdateInfo` with `latestVersion`, `currentVersion`, `releasePageUrl`, and optional `releaseNotes`. |
| `UpToDate`        | The check ran; the installed version is current.               |
| `CheckSkipped`    | The check did not run (throttled, or `currentVersion == 'dev'`). |
| `CheckError`      | The check failed (offline, rate-limited, malformed data). Never thrown — `check()` always resolves. |

Errors and skips are silent by intent: the app only prompts on
`UpdateAvailable`, and the throttle timestamp is stamped **only after a
successful check**, so an offline launch retries on the next launch instead of
being locked out for a full interval.

## Testing your integration

`ReleaseChecker` accepts an injected `http.Client` and clock, so tests need no
network:

```dart
class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('{"tag_name": "v9.9.9"}')),
        200,
      );
}

final checker = ReleaseChecker(
  owner: 'your-org',
  repo: 'your-app',
  currentVersion: '1.0.0',
  httpClient: _FakeClient(),
);
// await checker.check() → UpdateAvailable(v9.9.9)
```

Use `InMemoryUpdateCheckStore` as a non-persistent store in tests (or to check
on every launch).

## Android note

Opening the release page needs nothing beyond the standard `url_launcher`
setup: no new permission, and Android 11+ package visibility is satisfied by
declaring a VIEW intent for `https` in `AndroidManifest.xml`:

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.VIEW"/>
        <data android:scheme="https"/>
    </intent>
</queries>
```

## Behaviour details

- Requests go to `https://api.github.com/repos/{owner}/{repo}/releases/latest`
  with `Accept: application/vnd.github+json` and a `User-Agent` header — the
  GitHub REST API rejects requests without a `User-Agent` with 403, which
  would otherwise make updates silently never appear.
- `/releases/latest` **excludes drafts and pre-releases**: only finished,
  non-prerelease releases are visible to the checker. Keep that in mind when
  cutting releases.
- Version comparison strips one leading `v` and `+build` suffixes and compares
  numeric `major.minor.patch` (missing components are zero). Unparseable
  release tags or current versions produce `CheckError`, never a spurious
  "update available" or a silent "up to date".

## Running the package's own tests

```
flutter pub get
flutter analyze
flutter test
```
