const String smokeModeHappyPath = 'happy-path';
const String smokeModeContractCheck = 'contract-check';
const String smokeModePartialFailureResume = 'partial-failure-resume';

const Set<String> smokeModes = <String>{
  smokeModeHappyPath,
  smokeModeContractCheck,
  smokeModePartialFailureResume,
};

final class SmokeCommandOptions {
  const SmokeCommandOptions({
    required this.sourceProvider,
    required this.sourceUrl,
    required this.targetProvider,
    required this.targetUrl,
    required this.mode,
    required this.skipSetup,
    required this.skipTeardown,
    required this.cooldownSeconds,
    required this.pollIntervalSeconds,
    required this.pollTimeoutSeconds,
    required this.settingsProfile,
    required this.workdir,
    required this.quiet,
    required this.jsonOutput,
  });

  final String sourceProvider;
  final String sourceUrl;
  final String targetProvider;
  final String targetUrl;
  final String mode;
  final bool skipSetup;
  final bool skipTeardown;
  final int cooldownSeconds;
  final int pollIntervalSeconds;
  final int pollTimeoutSeconds;
  final String settingsProfile;
  final String workdir;
  final bool quiet;
  final bool jsonOutput;
}
