import 'package:gfrm_dart/src/config/arg_parsers.dart';
import 'package:test/test.dart';

void main() {
  group('CliParserCatalog', () {
    test('buildUsage returns non-empty string with commands listed', () {
      final String usage = CliParserCatalog.buildUsage();
      expect(usage, contains('migrate'));
      expect(usage, contains('demo'));
      expect(usage, contains('settings'));
    });

    test('buildSetupUsage returns non-empty string with profile option', () {
      final String usage = CliParserCatalog.buildSetupUsage();
      expect(usage, contains('--profile'));
      expect(usage, contains('setup'));
    });
  });
}
