import 'package:shared_preferences/shared_preferences.dart';

import 'update_throttle.dart';

/// The [SharedPreferences] key for the last successful check timestamp
/// (stored as `millisecondsSinceEpoch`).
const _kLastCheckKey = 'auto_upgrade.last_check';

/// A [UpdateCheckStore] backed by [SharedPreferences] — the store apps should
/// use in production so the throttle survives restarts. This is the only file
/// in the package that touches the plugin world.
class SharedPrefsUpdateCheckStore implements UpdateCheckStore {
  final SharedPreferences _prefs;

  const SharedPrefsUpdateCheckStore(this._prefs);

  @override
  Future<DateTime?> lastCheckAt() async {
    final ms = _prefs.getInt(_kLastCheckKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> markChecked(DateTime when) =>
      _prefs.setInt(_kLastCheckKey, when.millisecondsSinceEpoch);
}
