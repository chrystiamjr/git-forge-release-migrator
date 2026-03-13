import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/preflight_service.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:test/test.dart';

import '../../support/runtime_options_fixture.dart';

final class _SourceAdapter extends ProviderAdapter {
  @override
  String get name => 'stub-source';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://github.com/')) {
      throw ArgumentError('Invalid GitHub repository URL: $url');
    }

    return ProviderRef(
      provider: 'github',
      rawUrl: url,
      baseUrl: 'https://github.com',
      host: 'github.com',
      resource: 'acme/source',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    throw UnimplementedError();
  }
}

final class _TargetAdapter extends ProviderAdapter {
  @override
  String get name => 'stub-target';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://gitlab.com/')) {
      throw ArgumentError('Invalid GitLab repository URL: $url');
    }

    return ProviderRef(
      provider: 'gitlab',
      rawUrl: url,
      baseUrl: 'https://gitlab.com',
      host: 'gitlab.com',
      resource: 'acme/target',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    throw UnimplementedError();
  }
}

final class _BuggyTargetAdapter extends ProviderAdapter {
  @override
  String get name => 'buggy-target';

  @override
  ProviderRef parseUrl(String url) {
    throw StateError('unexpected parser failure');
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    throw UnimplementedError();
  }
}

ProviderRegistry _buildRegistry() {
  return ProviderRegistry(<String, ProviderAdapter>{
    'github': _SourceAdapter(),
    'gitlab': _TargetAdapter(),
  });
}

ProviderRegistry _buildBuggyRegistry() {
  return ProviderRegistry(<String, ProviderAdapter>{
    'github': _SourceAdapter(),
    'gitlab': _BuggyTargetAdapter(),
  });
}

void main() {
  group('PreflightService', () {
    test('classifies supported startup checks as ok', () {
      final PreflightService service = PreflightService(
        settingsLoader: () => <String, dynamic>{
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{},
          },
        },
      );
      final ProviderRegistry registry = _buildRegistry();

      final List<PreflightCheck> checks = service.evaluateStartup(
        buildRuntimeOptions(settingsProfile: 'work'),
        registry,
      );

      expect(checks.every((PreflightCheck check) => check.status == PreflightCheckStatus.ok), isTrue);
    });

    test('classifies missing settings profile as warning', () {
      final PreflightService service = PreflightService(
        settingsLoader: () => <String, dynamic>{
          'profiles': <String, dynamic>{
            'default': <String, dynamic>{},
          },
        },
      );

      final PreflightCheck check = service
          .evaluateStartup(
            buildRuntimeOptions(settingsProfile: 'work'),
            _buildRegistry(),
          )
          .firstWhere((PreflightCheck item) => item.field == PreflightService.fieldSettingsProfile);

      expect(check.status, PreflightCheckStatus.warning);
      expect(check.code, 'missing-settings-profile');
    });

    test('classifies missing tokens as blocking errors', () {
      final PreflightService service = PreflightService();

      final List<PreflightCheck> checks = service.evaluateStartup(
        buildRuntimeOptions(sourceToken: '', targetToken: ''),
        _buildRegistry(),
      );

      expect(PreflightService.hasBlockingErrors(checks), isTrue);
      expect(checks.where((PreflightCheck check) => check.isBlocking), hasLength(2));
    });

    test('rethrows unexpected URL parsing failures', () {
      final PreflightService service = PreflightService();

      expect(
        () => service.evaluateStartup(
          buildRuntimeOptions(),
          _buildBuggyRegistry(),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
