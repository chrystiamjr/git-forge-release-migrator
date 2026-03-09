import 'package:gfrm_dart/src/core/versioning.dart';
import 'package:test/test.dart';

void main() {
  group('versioning', () {
    test('versionLe compares semantic versions', () {
      expect(SemverUtils.versionLe('v1.2.3', 'v1.2.3'), isTrue);
      expect(SemverUtils.versionLe('v1.2.3', 'v1.2.4'), isTrue);
      expect(SemverUtils.versionLe('v1.3.0', 'v1.2.9'), isFalse);
    });

    test('throws for invalid tags', () {
      expect(() => SemverUtils.versionLe('1.2', '1.2.3'), throwsArgumentError);
    });
  });
}
