import 'package:gfrm_dart/src/config/validators.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigValidators', () {
    group('tokenModeIsValid', () {
      test('accepts env', () {
        expect(ConfigValidators.tokenModeIsValid('env'), isTrue);
      });

      test('accepts plain', () {
        expect(ConfigValidators.tokenModeIsValid('plain'), isTrue);
      });

      test('rejects unknown mode', () {
        expect(ConfigValidators.tokenModeIsValid('file'), isFalse);
        expect(ConfigValidators.tokenModeIsValid(''), isFalse);
      });
    });

    group('validateWorkerBounds', () {
      test('accepts valid bounds', () {
        expect(
          () => ConfigValidators.validateWorkerBounds(downloadWorkers: 4, releaseWorkers: 2),
          returnsNormally,
        );
      });

      test('accepts minimum bounds', () {
        expect(
          () => ConfigValidators.validateWorkerBounds(downloadWorkers: 1, releaseWorkers: 1),
          returnsNormally,
        );
      });

      test('accepts maximum bounds', () {
        expect(
          () => ConfigValidators.validateWorkerBounds(downloadWorkers: 16, releaseWorkers: 8),
          returnsNormally,
        );
      });

      test('rejects download workers below minimum', () {
        expect(
          () => ConfigValidators.validateWorkerBounds(downloadWorkers: 0, releaseWorkers: 1),
          throwsArgumentError,
        );
      });

      test('rejects download workers above maximum', () {
        expect(
          () => ConfigValidators.validateWorkerBounds(downloadWorkers: 17, releaseWorkers: 1),
          throwsArgumentError,
        );
      });

      test('rejects release workers below minimum', () {
        expect(
          () => ConfigValidators.validateWorkerBounds(downloadWorkers: 4, releaseWorkers: 0),
          throwsArgumentError,
        );
      });

      test('rejects release workers above maximum', () {
        expect(
          () => ConfigValidators.validateWorkerBounds(downloadWorkers: 4, releaseWorkers: 9),
          throwsArgumentError,
        );
      });
    });

    group('validateProviderValue', () {
      const Set<String> known = <String>{'github', 'gitlab', 'bitbucket'};

      test('accepts known provider', () {
        expect(
          () => ConfigValidators.validateProviderValue('source', 'github', known),
          returnsNormally,
        );
      });

      test('rejects unknown provider', () {
        expect(
          () => ConfigValidators.validateProviderValue('source', 'azure', known),
          throwsArgumentError,
        );
      });
    });

    group('validateTagRange', () {
      test('passes when both tags are empty', () {
        expect(() => ConfigValidators.validateTagRange('', ''), returnsNormally);
      });

      test('passes when only from-tag is set', () {
        expect(() => ConfigValidators.validateTagRange('v1.0.0', ''), returnsNormally);
      });

      test('passes when only to-tag is set', () {
        expect(() => ConfigValidators.validateTagRange('', 'v2.0.0'), returnsNormally);
      });

      test('passes when from <= to', () {
        expect(() => ConfigValidators.validateTagRange('v1.0.0', 'v2.0.0'), returnsNormally);
        expect(() => ConfigValidators.validateTagRange('v1.0.0', 'v1.0.0'), returnsNormally);
      });

      test('rejects when from > to', () {
        expect(
          () => ConfigValidators.validateTagRange('v2.0.0', 'v1.0.0'),
          throwsArgumentError,
        );
      });
    });

    group('validateDemoConfig', () {
      test('accepts valid demo config', () {
        expect(
          () => ConfigValidators.validateDemoConfig(demoReleases: 5, demoSleepSeconds: 1.0),
          returnsNormally,
        );
      });

      test('accepts boundary values', () {
        expect(
          () => ConfigValidators.validateDemoConfig(demoReleases: 1, demoSleepSeconds: 0),
          returnsNormally,
        );
        expect(
          () => ConfigValidators.validateDemoConfig(demoReleases: 100, demoSleepSeconds: 0),
          returnsNormally,
        );
      });

      test('rejects demo releases below minimum', () {
        expect(
          () => ConfigValidators.validateDemoConfig(demoReleases: 0, demoSleepSeconds: 1.0),
          throwsArgumentError,
        );
      });

      test('rejects demo releases above maximum', () {
        expect(
          () => ConfigValidators.validateDemoConfig(demoReleases: 101, demoSleepSeconds: 1.0),
          throwsArgumentError,
        );
      });

      test('rejects negative sleep seconds', () {
        expect(
          () => ConfigValidators.validateDemoConfig(demoReleases: 5, demoSleepSeconds: -0.1),
          throwsArgumentError,
        );
      });
    });

    group('validateTokenPresence', () {
      test('passes when both tokens are present', () {
        expect(
          () => ConfigValidators.validateTokenPresence('source-token', 'target-token'),
          returnsNormally,
        );
      });

      test('rejects empty source token', () {
        expect(
          () => ConfigValidators.validateTokenPresence('', 'target-token'),
          throwsArgumentError,
        );
      });

      test('rejects empty target token', () {
        expect(
          () => ConfigValidators.validateTokenPresence('source-token', ''),
          throwsArgumentError,
        );
      });
    });
  });
}
