import '../core/adapters/provider_adapter.dart';
import '../core/settings.dart';
import '../models/runtime_options.dart';
import '../providers/registry.dart';
import 'preflight_check.dart';

typedef SettingsLoader = Map<String, dynamic> Function();

class PreflightService {
  PreflightService({
    SettingsLoader? settingsLoader,
  }) : _settingsLoader = settingsLoader ?? SettingsManager.loadEffectiveSettings;

  static const String fieldCommand = 'command';
  static const String fieldProviderPair = 'provider_pair';
  static const String fieldSourceUrl = 'source_url';
  static const String fieldTargetUrl = 'target_url';
  static const String fieldSourceToken = 'source_token';
  static const String fieldTargetToken = 'target_token';
  static const String fieldSettingsProfile = 'settings_profile';

  final SettingsLoader _settingsLoader;

  List<PreflightCheck> evaluateCommand(RuntimeOptions options) {
    if (options.commandName == commandMigrate || options.commandName == commandResume) {
      return const <PreflightCheck>[
        PreflightCheck(
          status: PreflightCheckStatus.ok,
          code: 'supported-command',
          message: 'Command is supported for application-layer execution.',
          field: fieldCommand,
        ),
      ];
    }

    return <PreflightCheck>[
      PreflightCheck(
        status: PreflightCheckStatus.error,
        code: 'unsupported-command',
        message: 'RunService supports migrate and resume only. Received: ${options.commandName}',
        hint: 'Use gfrm migrate or gfrm resume.',
        field: fieldCommand,
      ),
    ];
  }

  List<PreflightCheck> evaluateStartup(
    RuntimeOptions options,
    ProviderRegistry registry,
  ) {
    final List<PreflightCheck> checks = <PreflightCheck>[];

    final PreflightCheck pairCheck = _providerPairCheck(options, registry);
    checks.add(pairCheck);

    final Map<String, dynamic> settingsPayload = _settingsLoader();
    checks.add(_settingsProfileCheck(options, settingsPayload));
    checks.add(_tokenCheck(options.sourceToken, side: 'source'));
    checks.add(_tokenCheck(options.targetToken, side: 'target'));

    if (pairCheck.status == PreflightCheckStatus.ok) {
      checks.addAll(_urlChecks(options, registry));
    }

    return checks;
  }

  static bool hasBlockingErrors(List<PreflightCheck> checks) {
    return checks.any((PreflightCheck check) => check.isBlocking);
  }

  static PreflightCheck? firstBlockingError(List<PreflightCheck> checks) {
    for (final PreflightCheck check in checks) {
      if (check.isBlocking) {
        return check;
      }
    }

    return null;
  }

  PreflightCheck _providerPairCheck(RuntimeOptions options, ProviderRegistry registry) {
    if (registry.pairStatus(options.sourceProvider, options.targetProvider) == 'enabled') {
      return const PreflightCheck(
        status: PreflightCheckStatus.ok,
        code: 'supported-provider-pair',
        message: 'Provider pair is supported.',
        field: fieldProviderPair,
      );
    }

    return PreflightCheck(
      status: PreflightCheckStatus.error,
      code: 'unsupported-provider-pair',
      message: 'Provider pair ${options.sourceProvider}->${options.targetProvider} is unsupported.',
      hint: 'Use one of the supported cross-provider migration pairs.',
      field: fieldProviderPair,
    );
  }

  List<PreflightCheck> _urlChecks(RuntimeOptions options, ProviderRegistry registry) {
    return <PreflightCheck>[
      _singleUrlCheck(
        registry: registry,
        provider: options.sourceProvider,
        rawUrl: options.sourceUrl,
        field: fieldSourceUrl,
        okCode: 'valid-source-url',
        errorCode: 'invalid-source-url',
      ),
      _singleUrlCheck(
        registry: registry,
        provider: options.targetProvider,
        rawUrl: options.targetUrl,
        field: fieldTargetUrl,
        okCode: 'valid-target-url',
        errorCode: 'invalid-target-url',
      ),
    ];
  }

  PreflightCheck _singleUrlCheck({
    required ProviderRegistry registry,
    required String provider,
    required String rawUrl,
    required String field,
    required String okCode,
    required String errorCode,
  }) {
    try {
      final ProviderAdapter adapter = registry.get(provider);
      adapter.parseUrl(rawUrl);
      return PreflightCheck(
        status: PreflightCheckStatus.ok,
        code: okCode,
        message: 'Repository URL is valid for $provider.',
        field: field,
      );
    } catch (exc) {
      return PreflightCheck(
        status: PreflightCheckStatus.error,
        code: errorCode,
        message: exc.toString(),
        hint: 'Provide a valid $provider repository URL.',
        field: field,
      );
    }
  }

  PreflightCheck _tokenCheck(String tokenValue, {required String side}) {
    if (tokenValue.trim().isNotEmpty) {
      return PreflightCheck(
        status: PreflightCheckStatus.ok,
        code: '$side-token-resolved',
        message: '${_labelForSide(side)} token resolved.',
        field: side == 'source' ? fieldSourceToken : fieldTargetToken,
      );
    }

    return PreflightCheck(
      status: PreflightCheckStatus.error,
      code: 'missing-$side-token',
      message: 'Missing ${_labelForSide(side).toLowerCase()} token.',
      hint: 'Provide --$side-token, a settings profile token, or a relevant environment variable.',
      field: side == 'source' ? fieldSourceToken : fieldTargetToken,
    );
  }

  PreflightCheck _settingsProfileCheck(
    RuntimeOptions options,
    Map<String, dynamic> settingsPayload,
  ) {
    final String profile = options.settingsProfile.trim();
    if (profile.isEmpty || profile == 'default') {
      return const PreflightCheck(
        status: PreflightCheckStatus.ok,
        code: 'settings-profile-ready',
        message: 'Settings profile readiness check passed.',
        field: fieldSettingsProfile,
      );
    }

    final dynamic profilesRaw = settingsPayload['profiles'];
    final Map<String, dynamic> profiles = profilesRaw is Map<String, dynamic> ? profilesRaw : <String, dynamic>{};
    if (profiles.containsKey(profile)) {
      return PreflightCheck(
        status: PreflightCheckStatus.ok,
        code: 'settings-profile-ready',
        message: 'Settings profile $profile is available.',
        field: fieldSettingsProfile,
      );
    }

    return PreflightCheck(
      status: PreflightCheckStatus.warning,
      code: 'missing-settings-profile',
      message: 'Settings profile $profile was not found in effective settings.',
      hint: 'The run can continue if tokens were resolved elsewhere, but profile-backed settings will not apply.',
      field: fieldSettingsProfile,
    );
  }

  static String _labelForSide(String side) {
    return side == 'source' ? 'Source' : 'Target';
  }
}
