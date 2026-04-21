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
    this.fromTag = '',
    this.toTag = '',
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
  final String fromTag;
  final String toTag;

  bool get canValidateConnections => sourceUrl.trim().isNotEmpty && targetUrl.trim().isNotEmpty;

  bool get canContinueFromStepOne => sourceValidated && targetValidated;

  List<String> get matchingTags {
    if (!_isEmptyOrStrictSemver(fromTag) || !_isEmptyOrStrictSemver(toTag)) {
      return <String>[];
    }

    return sampleTags
        .where((String tag) {
          if (!_isStrictSemver(tag)) {
            return false;
          }
          final bool afterFrom = fromTag.isEmpty || _isSemverGreaterOrEqual(tag, fromTag);
          final bool beforeTo = toTag.isEmpty || _isSemverLessOrEqual(tag, toTag);
          return afterFrom && beforeTo;
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
      fromTag: _validatedRangeTag(fromTag, 'fromTag'),
      toTag: _validatedRangeTag(toTag, 'toTag'),
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
    String? fromTag,
    String? toTag,
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
      fromTag: fromTag ?? this.fromTag,
      toTag: toTag ?? this.toTag,
    );
  }

  static bool _isSemverGreaterOrEqual(String tag, String minTag) {
    return _compareSemver(tag, minTag) >= 0;
  }

  static bool _isSemverLessOrEqual(String tag, String maxTag) {
    return _compareSemver(tag, maxTag) <= 0;
  }

  static int _compareSemver(String a, String b) {
    final List<int> aParts = _extractSemverParts(a);
    final List<int> bParts = _extractSemverParts(b);

    for (int i = 0; i < 3; i++) {
      if (aParts[i] != bParts[i]) {
        return aParts[i].compareTo(bParts[i]);
      }
    }
    return 0;
  }

  static bool _isStrictSemver(String tag) {
    return RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag);
  }

  static bool _isEmptyOrStrictSemver(String tag) {
    final String trimmed = tag.trim();
    return trimmed.isEmpty || _isStrictSemver(trimmed);
  }

  static String _validatedRangeTag(String tag, String fieldName) {
    final String trimmed = tag.trim();
    if (trimmed.isEmpty || _isStrictSemver(trimmed)) {
      return trimmed;
    }

    throw ArgumentError.value(tag, fieldName, 'Expected strict semver tag format vX.Y.Z.');
  }

  static List<int> _extractSemverParts(String tag) {
    final RegExp semverRegex = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$');
    final RegExpMatch? match = semverRegex.firstMatch(tag);

    if (match == null || match.groupCount < 3) {
      return <int>[0, 0, 0];
    }

    return <int>[int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!)];
  }
}
