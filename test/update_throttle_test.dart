import 'package:auto_upgrade/src/update_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryUpdateCheckStore', () {
    test('starts with a null last-check timestamp', () async {
      final store = InMemoryUpdateCheckStore();
      expect(await store.lastCheckAt(), isNull);
    });

    test('round-trips a marked timestamp', () async {
      final store = InMemoryUpdateCheckStore();
      final when = DateTime(2026, 1, 15, 10, 30);

      await store.markChecked(when);

      expect(await store.lastCheckAt(), when);
    });

    test('overwrites the timestamp on a later mark', () async {
      final store = InMemoryUpdateCheckStore();
      await store.markChecked(DateTime(2026, 1, 1));
      final later = DateTime(2026, 2, 2);

      await store.markChecked(later);

      expect(await store.lastCheckAt(), later);
    });
  });
}
