/// Persists the timestamp of the last *successful* update check so
/// [ReleaseChecker] can throttle itself (one network round-trip per interval).
library;

/// Where the checker records when it last completed a successful check.
///
/// The timestamp is stamped at *check* time (not at prompt time): a launch
/// killed before the UI shows a dialog still counts as checked. Only
/// successful API round-trips are recorded — a `CheckError` (offline,
/// rate-limited) does not push the next check out by a full interval.
abstract interface class UpdateCheckStore {
  /// When the last successful check happened, or `null` if never.
  Future<DateTime?> lastCheckAt();

  /// Record a successful check that happened at [when].
  Future<void> markChecked(DateTime when);
}

/// A non-persistent [UpdateCheckStore]: every process start counts as "never
/// checked". Handy for tests, or for apps that want to check on every launch.
class InMemoryUpdateCheckStore implements UpdateCheckStore {
  DateTime? _last;

  @override
  Future<DateTime?> lastCheckAt() async => _last;

  @override
  Future<void> markChecked(DateTime when) {
    _last = when;
    return Future.value();
  }
}
