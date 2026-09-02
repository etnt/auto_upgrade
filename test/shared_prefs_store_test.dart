import 'package:auto_upgrade/src/shared_prefs_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The one package test file that needs the plugin binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsUpdateCheckStore', () {
    test('round-trips the last-check timestamp', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsUpdateCheckStore(prefs);
      final when = DateTime(2026, 4, 1, 8, 15);

      expect(await store.lastCheckAt(), isNull);
      await store.markChecked(when);

      expect(await store.lastCheckAt(), when);
    });

    test('persists across a simulated restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await SharedPrefsUpdateCheckStore(prefs)
          .markChecked(DateTime(2026, 4, 2));

      // A fresh store over the same (mock-persisted) prefs sees the write.
      final reloaded = SharedPrefsUpdateCheckStore(prefs);
      expect(await reloaded.lastCheckAt(), DateTime(2026, 4, 2));
    });
  });
}
