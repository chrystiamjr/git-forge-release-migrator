import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/features/new_migration/domain/migration_provider_option.dart';

final class NewMigrationWizardState {
  const NewMigrationWizardState({
    this.step = 1,
    this.sourceProvider = MigrationProviderOption.github,
    this.targetProvider = MigrationProviderOption.gitlab,
    this.sourceUrl = '',
    this.targetUrl = '',
    this.sourceToken = '',
    this.targetToken = '',
    this.sourceValidated = false,
    this.targetValidated = false,
    this.migrateTags = true,
    this.migrateReleases = true,
    this.migrateReleaseAssets = true,
    this.dryRun = true,
    this.settingsProfile = 'default',
    this.includePattern = 'v*',
    this.excludePattern = '',
  });

  static const List<String> sampleTags = <String>[
    'v2.1.0',
    'v2.0.1',
    'v2.0.0',
    'v1.9.0',
    'v1.8.5',
    'v1.0.0',
    'v0.9.0-beta',
    'release-2024-01',
  ];

  final int step;
  final MigrationProviderOption sourceProvider;
  final MigrationProviderOption targetProvider;
  final String sourceUrl;
  final String targetUrl;
  final String sourceToken;
  final String targetToken;
  final bool sourceValidated;
  final bool targetValidated;
  final bool migrateTags;
  final bool migrateReleases;
  final bool migrateReleaseAssets;
  final bool dryRun;
  final String settingsProfile;
  final String includePattern;
  final String excludePattern;

  bool get canValidateConnections => sourceUrl.trim().isNotEmpty && targetUrl.trim().isNotEmpty;

  bool get canContinueFromStepOne => sourceValidated && targetValidated;

  List<String> get matchingTags {
    return sampleTags
        .where((String tag) {
          final bool included = _matchesGlob(tag, includePattern);
          final bool excluded = excludePattern.trim().isNotEmpty && _matchesGlob(tag, excludePattern);
          return included && !excluded;
        })
        .toList(growable: false);
  }

  DesktopRunStartRequest toRunStartRequest() {
    return DesktopRunStartRequest(
      sourceProvider: sourceProvider.id,
      sourceUrl: sourceUrl.trim(),
      sourceToken: sourceToken.trim(),
      targetProvider: targetProvider.id,
      targetUrl: targetUrl.trim(),
      targetToken: targetToken.trim(),
      settingsProfile: settingsProfile.trim(),
      fromTag: includePattern.trim(),
      toTag: excludePattern.trim(),
      skipTagMigration: !migrateTags,
      skipReleaseMigration: !migrateReleases,
      skipReleaseAssetMigration: !migrateReleaseAssets,
      dryRun: dryRun,
    );
  }

  NewMigrationWizardState copyWith({
    int? step,
    MigrationProviderOption? sourceProvider,
    MigrationProviderOption? targetProvider,
    String? sourceUrl,
    String? targetUrl,
    String? sourceToken,
    String? targetToken,
    bool? sourceValidated,
    bool? targetValidated,
    bool? migrateTags,
    bool? migrateReleases,
    bool? migrateReleaseAssets,
    bool? dryRun,
    String? settingsProfile,
    String? includePattern,
    String? excludePattern,
  }) {
    return NewMigrationWizardState(
      step: step ?? this.step,
      sourceProvider: sourceProvider ?? this.sourceProvider,
      targetProvider: targetProvider ?? this.targetProvider,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      targetUrl: targetUrl ?? this.targetUrl,
      sourceToken: sourceToken ?? this.sourceToken,
      targetToken: targetToken ?? this.targetToken,
      sourceValidated: sourceValidated ?? this.sourceValidated,
      targetValidated: targetValidated ?? this.targetValidated,
      migrateTags: migrateTags ?? this.migrateTags,
      migrateReleases: migrateReleases ?? this.migrateReleases,
      migrateReleaseAssets: migrateReleaseAssets ?? this.migrateReleaseAssets,
      dryRun: dryRun ?? this.dryRun,
      settingsProfile: settingsProfile ?? this.settingsProfile,
      includePattern: includePattern ?? this.includePattern,
      excludePattern: excludePattern ?? this.excludePattern,
    );
  }

  static bool _matchesGlob(String value, String pattern) {
    final String normalizedPattern = pattern.trim().isEmpty ? '*' : pattern.trim();
    final String escaped = RegExp.escape(normalizedPattern).replaceAll(r'\*', '.*');
    return RegExp('^$escaped\$').hasMatch(value);
  }
}
