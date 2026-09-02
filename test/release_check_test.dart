import 'dart:async';
import 'dart:convert';

import 'package:auto_upgrade/src/release_check.dart';
import 'package:auto_upgrade/src/update_throttle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A hand-rolled fake [http.Client] that records requests and serves a canned
/// response (or throws), FakeTransport-style.
class _FakeClient extends http.BaseClient {
  final int statusCode;
  final String body;
  final Object? error;
  final List<(Uri url, Map<String, String> headers)> requests = [];

  _FakeClient({
    this.statusCode = 200,
    String? responseBody,
    this.error,
  }) : body = responseBody ?? '';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add((request.url, request.headers));
    if (error != null) throw error!;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
    );
  }
}

const _releaseJson = '''
{
  "tag_name": "v1.2.0",
  "html_url": "https://github.com/example/app/releases/tag/v1.2.0",
  "body": "What's new: faster scans."
}
''';

ReleaseChecker _checkerWith(
  _FakeClient client, {
  String currentVersion = '1.0.0',
  UpdateCheckStore? checkStore,
  DateTime Function()? now,
}) {
  return ReleaseChecker(
    owner: 'example',
    repo: 'app',
    currentVersion: currentVersion,
    httpClient: client,
    checkStore: checkStore,
    now: now,
  );
}

void main() {
  test('newer tag resolves to UpdateAvailable with the release page URL',
      () async {
    final client = _FakeClient(responseBody: _releaseJson);
    final checker = _checkerWith(client, currentVersion: '1.0.0');

    final result = await checker.check();

    expect(result, isA<UpdateAvailable>());
    final info = (result as UpdateAvailable).info;
    expect(info.latestVersion, '1.2.0');
    expect(info.currentVersion, '1.0.0');
    expect(
      info.releasePageUrl,
      'https://github.com/example/app/releases/tag/v1.2.0',
    );
    expect(info.releaseNotes, "What's new: faster scans.");
  });

  test('releasePageUrl falls back to the releases/latest page', () async {
    final client = _FakeClient(
      responseBody: '{"tag_name": "v1.2.0", "body": null}',
    );
    final checker = _checkerWith(client);

    final result = await checker.check();

    final info = (result as UpdateAvailable).info;
    expect(
      info.releasePageUrl,
      'https://github.com/example/app/releases/latest',
    );
    expect(info.releaseNotes, isNull);
  });

  test('equal tag resolves to UpToDate', () async {
    final client = _FakeClient(
      responseBody: '{"tag_name": "v1.0.0"}',
    );
    final checker = _checkerWith(client, currentVersion: '1.0.0');

    expect(await checker.check(), isA<UpToDate>());
  });

  test('older tag resolves to UpToDate, never a spurious update', () async {
    final client = _FakeClient(
      responseBody: '{"tag_name": "v0.9.9"}',
    );
    final checker = _checkerWith(client, currentVersion: '1.0.0');

    expect(await checker.check(), isA<UpToDate>());
  });

  test('HTTP error statuses resolve to CheckError', () async {
    for (final status in [403, 404, 500]) {
      final client = _FakeClient(statusCode: status, responseBody: '{}');
      final checker = _checkerWith(client);

      final result = await checker.check();

      expect(result, isA<CheckError>(), reason: 'status $status');
    }
  });

  test('transport exceptions resolve to CheckError', () async {
    final client = _FakeClient(error: Exception('offline'));
    final checker = _checkerWith(client);

    final result = await checker.check();

    expect(result, isA<CheckError>());
  });

  test('malformed tag_name resolves to CheckError', () async {
    final client = _FakeClient(
      responseBody: '{"tag_name": "not-a-version"}',
    );
    final checker = _checkerWith(client);

    final result = await checker.check();

    expect(result, isA<CheckError>());
  });

  test('missing tag_name resolves to CheckError', () async {
    final client = _FakeClient(responseBody: '{"html_url": "x"}');
    final checker = _checkerWith(client);

    expect(await checker.check(), isA<CheckError>());
  });

  test('malformed non-dev currentVersion resolves to CheckError', () async {
    final client = _FakeClient(responseBody: '{"tag_name": "v2.0.0"}');
    final checker = _checkerWith(client, currentVersion: 'local-build');

    final result = await checker.check();

    expect(result, isA<CheckError>());
    expect(client.requests, isEmpty, reason: 'no HTTP for a bad local version');
  });

  test('dev currentVersion skips with zero HTTP calls', () async {
    final client = _FakeClient(responseBody: _releaseJson);
    final checker =
        _checkerWith(client, currentVersion: ReleaseChecker.devVersion);

    final result = await checker.check();

    expect(result, isA<CheckSkipped>());
    expect(client.requests, isEmpty);
  });

  test('sends the GitHub-required Accept and User-Agent headers', () async {
    final client = _FakeClient(responseBody: _releaseJson);
    final checker = _checkerWith(client);

    await checker.check();

    expect(client.requests, hasLength(1));
    final (url, headers) = client.requests.single;
    expect(
      url,
      Uri.https('api.github.com', '/repos/example/app/releases/latest'),
    );
    expect(headers['Accept'], 'application/vnd.github+json');
    expect(headers['User-Agent'], 'auto_upgrade (example/app)');
  });

  test('injected clock is honoured for the throttle window', () async {
    final client = _FakeClient(responseBody: '{"tag_name": "v1.0.0"}');
    final store = InMemoryUpdateCheckStore();
    var time = DateTime(2026, 5, 1);
    final checker = _checkerWith(
      client,
      checkStore: store,
      now: () => time,
    );

    await store.markChecked(DateTime(2026, 5, 1, 23, 59));
    time = DateTime(2026, 5, 2); // 1 minute later — inside the interval.
    expect(await checker.check(), isA<CheckSkipped>());

    time = DateTime(2026, 5, 3); // Beyond the interval.
    expect(await checker.check(), isA<UpToDate>());
  });

  group('throttling', () {
    test('a second check within the interval is skipped with zero HTTP',
        () async {
      var time = DateTime(2026, 3, 1, 12);
      final client = _FakeClient(responseBody: '{"tag_name": "v1.0.0"}');
      final store = InMemoryUpdateCheckStore();
      final checker = _checkerWith(
        client,
        checkStore: store,
        now: () => time,
      );

      // First check runs (and is recorded on success).
      expect(await checker.check(), isA<UpToDate>());
      expect(client.requests, hasLength(1));

      // Advance 1 hour (< the default 24 h interval).
      time = time.add(const Duration(hours: 1));
      expect(await checker.check(), isA<CheckSkipped>());
      expect(client.requests, hasLength(1));
    });

    test('a check after the interval hits the network again', () async {
      var time = DateTime(2026, 3, 1, 12);
      final client = _FakeClient(responseBody: '{"tag_name": "v1.0.0"}');
      final checker = _checkerWith(
        client,
        checkStore: InMemoryUpdateCheckStore(),
        now: () => time,
      );

      await checker.check();
      time = time.add(const Duration(hours: 25));

      expect(await checker.check(), isA<UpToDate>());
      expect(client.requests, hasLength(2));
    });

    test('an error does not stamp the throttle; next check hits the network',
        () async {
      final erroring = _FakeClient(statusCode: 500, responseBody: '{}');
      final ok = _FakeClient(responseBody: '{"tag_name": "v1.0.0"}');
      final store = InMemoryUpdateCheckStore();
      final checker = _checkerWith(erroring, checkStore: store);

      expect(await checker.check(), isA<CheckError>());

      // A healthy checker over the same store: still outside the throttle
      // because the failed check was never recorded.
      final recovering = ReleaseChecker(
        owner: 'example',
        repo: 'app',
        currentVersion: '1.0.0',
        httpClient: ok,
        checkStore: store,
        now: () => DateTime(2026, 3, 1, 12),
      );
      expect(await recovering.check(), isA<UpToDate>());
      expect(ok.requests, hasLength(1));
      expect(await store.lastCheckAt(), isNotNull);
    });

    test('no store means every check runs', () async {
      final client = _FakeClient(responseBody: '{"tag_name": "v1.0.0"}');
      final checker = _checkerWith(client);

      expect(await checker.check(), isA<UpToDate>());
      expect(await checker.check(), isA<UpToDate>());
      expect(client.requests, hasLength(2));
    });
  });
}
