import 'package:gfrm_dart/src/providers/provider_common.dart';
import 'package:test/test.dart';

void main() {
  group('provider common', () {
    test('normalizeRepositoryUrl strips .git, query and fragment', () {
      final String normalized = ProviderCommon.normalizeRepositoryUrl(
        'https://github.com/acme/repo.git?foo=1#section',
      );

      expect(normalized, 'https://github.com/acme/repo');
    });

    test('mapFrom and mapListFrom return safe defaults', () {
      expect(ProviderCommon.mapFrom('invalid'), <String, dynamic>{});
      expect(ProviderCommon.mapListFrom('invalid'), <Map<String, dynamic>>[]);
    });

    test('mapListFrom keeps only map-like entries', () {
      final List<Map<String, dynamic>> mapped = ProviderCommon.mapListFrom(<dynamic>[
        <String, dynamic>{'name': 'a'},
        'skip',
        <String, dynamic>{'name': 'b'},
      ]);

      expect(mapped.length, 2);
      expect(mapped[0]['name'], 'a');
      expect(mapped[1]['name'], 'b');
    });
  });
}
