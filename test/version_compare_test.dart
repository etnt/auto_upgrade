import 'package:flutter_test/flutter_test.dart';
import 'package:auto_upgrade/src/version_compare.dart';

void main() {
  group('stripVersionTag', () {
    test('strips one leading v and +build suffixes', () {
      expect(stripVersionTag('v1.2.0+3'), '1.2.0');
      expect(stripVersionTag('V2.0.0'), '2.0.0');
      expect(stripVersionTag('1.2.0'), '1.2.0');
      expect(stripVersionTag('1.2.0+42'), '1.2.0');
    });

    test('leaves embedded v alone', () {
      expect(stripVersionTag('1.2.0+v3'), '1.2.0');
      expect(stripVersionTag('av1'), 'av1');
    });
  });

  group('compareVersions', () {
    test('equal versions compare as zero', () {
      expect(compareVersions('1.2.0', '1.2.0'), 0);
      expect(compareVersions('0.0.1', '0.0.1'), 0);
    });

    test('older/newer per component', () {
      expect(compareVersions('1.0.0', '2.0.0'), isNegative);
      expect(compareVersions('2.0.0', '1.0.0'), isPositive);
      expect(compareVersions('1.1.0', '1.2.0'), isNegative);
      expect(compareVersions('1.2.0', '1.1.0'), isPositive);
      expect(compareVersions('1.2.3', '1.2.4'), isNegative);
      expect(compareVersions('1.2.4', '1.2.3'), isPositive);
    });

    test('v prefix and +build suffix are ignored', () {
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      expect(compareVersions('1.2.0+3', 'v1.2.0+9'), 0);
      expect(compareVersions('v1.3.0+1', '1.2.9+99'), isPositive);
    });

    test('two-component versions equal three-component', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1', '1.0.0'), 0);
      expect(compareVersions('1.2', '1.3'), isNegative);
    });

    test('unparseable versions throw FormatException', () {
      expect(() => compareVersions('banana', '1.0.0'), throwsFormatException);
      expect(() => compareVersions('1.0.0', ''), throwsFormatException);
      expect(() => compareVersions('-1.0.0', '1.0.0'), throwsFormatException);
      expect(() => compareVersions('1.x.0', '1.0.0'), throwsFormatException);
      expect(
        () => compareVersions('1.2.3.4', '1.2.3'),
        throwsFormatException,
      );
    });
  });
}
