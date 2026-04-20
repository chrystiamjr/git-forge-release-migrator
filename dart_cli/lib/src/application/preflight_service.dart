import '../core/adapters/provider_adapter.dart';
import '../core/types/canonical_release.dart';
import '../core/settings.dart';
import '../migrations/selection.dart';
import '../models/migration_context.dart';
import '../models/runtime_options.dart';
import '../providers/registry.dart';
import 'missing_target_commit.dart';
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
  static const String fieldTagHistory = 'tag_history';

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
    } on ArgumentError catch (exc) {
      return PreflightCheck(
        status: PreflightCheckStatus.error,
        code: errorCode,
        message: exc.toString(),
        hint: 'Provide a valid $provider repository URL.',
        field: field,
      );
    } on FormatException catch (exc) {
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

  Future<List<MissingTargetCommit>> findMissingTargetCommits(MigrationContext ctx) async {
    if (ctx.options.skipTagMigration || ctx.selectedTags.isEmpty) {
      return const <MissingTargetCommit>[];
    }

    final List<MissingTargetCommit> missing = <MissingTargetCommit>[];
    final Map<String, bool> commitAvailability = <String, bool>{};

    for (final String tag in ctx.selectedTags) {
      if (ctx.targetTags.contains(tag)) {
        continue;
      }

      final Map<String, dynamic>? releasePayload = SelectionService.releaseByTag(ctx.releases, tag);
      final CanonicalRelease canonical = ctx.source.toCanonicalRelease(releasePayload ?? <String, dynamic>{});
      final String commitSha = await ctx.source.resolveCommitShaForMigration(
        ctx.sourceRef,
        ctx.options.sourceToken,
        tag,
        canonical,
      );
      if (commitSha.isEmpty) {
        continue;
      }

      final bool exists = commitAvailability.containsKey(commitSha)
          ? commitAvailability[commitSha]!
          : await ctx.target.commitExists(ctx.targetRef, ctx.options.targetToken, commitSha);
      commitAvailability[commitSha] = exists;
      if (!exists) {
        missing.add(MissingTargetCommit(tag: tag, commitSha: commitSha));
      }
    }

    return missing;
  }

  PreflightCheck? buildSkipTagsSafetyCheck(MigrationContext ctx) {
    if (!ctx.options.skipTagMigration) {
      return null;
    }

    if (ctx.targetTags.isEmpty) {
      final String targetProvider = SelectionService.capitalizeProvider(ctx.options.targetProvider);
      return PreflightCheck(
        status: PreflightCheckStatus.error,
        code: 'skip-tags-unsafe',
        message: '--skip-tags is not safe when $targetProvider has no existing tags.',
        hint:
            'The target repository must already contain all tags you plan to migrate. Since $targetProvider is empty, '
            '--skip-tags would result in releases without corresponding tag references. Either: (1) migrate tags by removing --skip-tags, '
            'or (2) ensure $targetProvider already has the required tags from a previous migration.',
        field: fieldTagHistory,
      );
    }

    return null;
  }

  PreflightCheck buildMissingTargetCommitCheck(
    MigrationContext ctx,
    List<MissingTargetCommit> missing,
  ) {
    final MissingTargetCommit first = missing.first;
    final String targetProvider = SelectionService.capitalizeProvider(ctx.options.targetProvider);
    final String previewTags = missing.take(3).map((MissingTargetCommit item) => item.tag).join(', ');
    final String suffix = missing.length > 3 ? ', ...' : '';

    return PreflightCheck(
      status: PreflightCheckStatus.error,
      code: 'missing-target-commit-history',
      message:
          '$targetProvider is missing commit object(s) required to create ${missing.length} tag(s). Example: ${first.tag} -> ${first.commitSha}. Affected tags: $previewTags$suffix.',
      hint: _missingTargetCommitHint(ctx, missing),
      field: fieldTagHistory,
    );
  }

  String _missingTargetCommitHint(
    MigrationContext ctx,
    List<MissingTargetCommit> missing,
  ) {
    final StringBuffer buffer = StringBuffer();
    final int previewCount = missing.length < 5 ? missing.length : 5;
    final String targetProvider = SelectionService.capitalizeProvider(ctx.options.targetProvider);

    buffer.writeln(
        'Preflight stopped before creating tags because the target repository does not contain the commit object(s) referenced by the source tags.');
    buffer.writeln();
    buffer.writeln('Missing tag -> commit examples:');
    for (final MissingTargetCommit item in missing.take(previewCount)) {
      buffer.writeln('- ${item.tag} -> ${item.commitSha}');
    }
    if (missing.length > previewCount) {
      buffer.writeln('- ...');
    }
    buffer.writeln();
    buffer.writeln('Recommended remediations:');
    buffer.writeln('1. Align the target history first (best when the target repository is new or disposable):');
    buffer.writeln('   git clone --mirror ${ctx.options.sourceUrl} gfrm-history-mirror.git');
    buffer.writeln('   cd gfrm-history-mirror.git');
    buffer.writeln('   git push --mirror ${ctx.options.targetUrl}');
    buffer.writeln();
    buffer.writeln('2. Publish source history to a helper branch without overwriting the target default branch:');
    buffer.writeln('   git clone ${ctx.options.sourceUrl} gfrm-history-seed');
    buffer.writeln('   cd gfrm-history-seed');
    buffer.writeln('   git remote add target ${ctx.options.targetUrl}');
    buffer.writeln('   git push target refs/heads/<source-default-branch>:refs/heads/gfrm-source-main');
    buffer.writeln();
    buffer.writeln(
        '3. For shared test data repos, ensure both forges contain the same seed/history before migrating tags.');
    buffer.writeln();
    buffer.writeln('Target platform options:');
    switch (ctx.options.targetProvider) {
      case 'github':
        buffer.writeln(
            '- GitHub Importer: https://docs.github.com/en/migrations/importing-source-code/using-github-importer/importing-a-repository-with-github-importer?apiVersion=2022-11-28');
        buffer.writeln(
            '- Git mirror/duplicate repository: https://docs.github.com/en/repositories/creating-and-managing-repositories/duplicating-a-repository');
        break;
      case 'gitlab':
        buffer.writeln('- GitLab repository mirroring: https://docs.gitlab.com/ee/user/project/repository/mirror/');
        break;
      case 'bitbucket':
        buffer.writeln(
            '- Bitbucket Cloud import repository: https://support.atlassian.com/bitbucket-cloud/docs/import-a-repository/');
        break;
      default:
        buffer.writeln('- Align the target history using your forge import or mirroring feature.');
    }
    buffer.writeln();
    buffer.write(
        'Use --skip-tags only if the target already has the requested tags. It is not safe for missing target tags in $targetProvider.');
    return buffer.toString();
  }
}
