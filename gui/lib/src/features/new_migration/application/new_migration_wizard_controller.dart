import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/domain/migration_provider_option.dart';

final StateNotifierProvider<NewMigrationWizardController, NewMigrationWizardState> newMigrationWizardProvider =
    StateNotifierProvider<NewMigrationWizardController, NewMigrationWizardState>(NewMigrationWizardController.new);

final class NewMigrationWizardController extends StateNotifier<NewMigrationWizardState> {
  NewMigrationWizardController(Ref ref) : super(const NewMigrationWizardState());

  void selectSourceProvider(MigrationProviderOption provider) {
    state = state.copyWith(sourceProvider: provider, sourceValidated: false);
  }

  void selectTargetProvider(MigrationProviderOption provider) {
    state = state.copyWith(targetProvider: provider, targetValidated: false);
  }

  void updateSourceUrl(String value) {
    state = state.copyWith(sourceUrl: value, sourceValidated: false);
  }

  void updateTargetUrl(String value) {
    state = state.copyWith(targetUrl: value, targetValidated: false);
  }

  void updateSourceToken(String value) {
    state = state.copyWith(sourceToken: value);
  }

  void updateTargetToken(String value) {
    state = state.copyWith(targetToken: value);
  }

  void validateConnections() {
    state = state.copyWith(
      sourceValidated: state.sourceUrl.trim().isNotEmpty,
      targetValidated: state.targetUrl.trim().isNotEmpty,
    );
  }

  void goToStep(int step) {
    state = state.copyWith(step: step.clamp(1, 2));
  }

  void setMigrateTags(bool value) {
    state = state.copyWith(migrateTags: value);
  }

  void setMigrateReleases(bool value) {
    state = state.copyWith(migrateReleases: value);
  }

  void setMigrateReleaseAssets(bool value) {
    state = state.copyWith(migrateReleaseAssets: value);
  }

  void setDryRun(bool value) {
    state = state.copyWith(dryRun: value);
  }

  void updateSettingsProfile(String value) {
    state = state.copyWith(settingsProfile: value);
  }

  void updateIncludePattern(String value) {
    state = state.copyWith(includePattern: value);
  }

  void updateExcludePattern(String value) {
    state = state.copyWith(excludePattern: value);
  }
}
