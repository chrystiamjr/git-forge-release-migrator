import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:test/test.dart';

void main() {
  group('provider registry', () {
    test('defaults exposes github gitlab and bitbucket', () {
      final ProviderRegistry registry = ProviderRegistry.defaults();

      expect(registry.get('github').name, 'github');
      expect(registry.get('gitlab').name, 'gitlab');
      expect(registry.get('bitbucket').name, 'bitbucket');
    });

    test('pairStatus returns enabled only for cross-provider known pairs', () {
      final ProviderRegistry registry = ProviderRegistry.defaults();

      expect(registry.pairStatus('github', 'gitlab'), 'enabled');
      expect(registry.pairStatus('github', 'github'), 'unsupported');
      expect(registry.pairStatus('unknown', 'gitlab'), 'unsupported');
    });

    test('requireSupportedPair throws for unsupported combinations', () {
      final ProviderRegistry registry = ProviderRegistry.defaults();

      expect(() => registry.requireSupportedPair('github', 'github'), throwsArgumentError);
      expect(() => registry.requireSupportedPair('unknown', 'gitlab'), throwsArgumentError);
      expect(() => registry.requireSupportedPair('github', 'gitlab'), returnsNormally);
    });

    test('get throws for unknown provider', () {
      final ProviderRegistry registry = ProviderRegistry.defaults();

      expect(() => registry.get('azuredevops'), throwsArgumentError);
    });
  });
}
