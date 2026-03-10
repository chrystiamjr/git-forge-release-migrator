import '../core/versioning.dart';

final class ConfigValidators {
  const ConfigValidators._();

  static bool tokenModeIsValid(String mode) {
    return const <String>{'env', 'plain'}.contains(mode);
  }

  static void validateWorkerBounds({
    required int downloadWorkers,
    required int releaseWorkers,
  }) {
    if (downloadWorkers < 1 || downloadWorkers > 16) {
      throw ArgumentError('--download-workers must be between 1 and 16');
    }

    if (releaseWorkers < 1 || releaseWorkers > 8) {
      throw ArgumentError('--release-workers must be between 1 and 8');
    }
  }

  static void validateProviderValue(String label, String provider, Set<String> knownProviders) {
    if (!knownProviders.contains(provider)) {
      throw ArgumentError('Unsupported $label provider: $provider');
    }
  }

  static void validateTagRange(String fromTag, String toTag) {
    if (fromTag.isNotEmpty && toTag.isNotEmpty && !SemverUtils.versionLe(fromTag, toTag)) {
      throw ArgumentError('Invalid range: --from-tag ($fromTag) must be <= --to-tag ($toTag)');
    }
  }

  static void validateDemoConfig({
    required int demoReleases,
    required double demoSleepSeconds,
  }) {
    if (demoReleases < 1 || demoReleases > 100) {
      throw ArgumentError('--demo-releases must be between 1 and 100');
    }

    if (demoSleepSeconds < 0) {
      throw ArgumentError('--demo-sleep-seconds must be >= 0');
    }
  }

  static void validateTokenPresence(String sourceToken, String targetToken) {
    if (sourceToken.isEmpty) {
      throw ArgumentError(
        'Missing source token. Configure it via settings profile token or relevant env variable.',
      );
    }

    if (targetToken.isEmpty) {
      throw ArgumentError(
        'Missing target token. Configure it via settings profile token or relevant env variable.',
      );
    }
  }
}
