import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gfrm_gui/src/application/run/contracts/desktop_run_controller.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/domain/migration_provider_option.dart';

final StateNotifierProvider<NewMigrationWizardController, NewMigrationWizardState> newMigrationWizardProvider =
    StateNotifierProvider<NewMigrationWizardController, NewMigrationWizardState>(NewMigrationWizardController.new);

final class NewMigrationWizardController extends StateNotifier<NewMigrationWizardState> {
  NewMigrationWizardController(_) : super(const NewMigrationWizardState());

  void selectSourceProvider(MigrationProviderOption provider) {
    state = state.copyWith(
      sourceProvider: provider,
      sourceValidated: false,
      preflightSummary: const DesktopPreflightSummary.initial(),
    );
  }

  void selectTargetProvider(MigrationProviderOption provider) {
    state = state.copyWith(
      targetProvider: provider,
      targetValidated: false,
      preflightSummary: const DesktopPreflightSummary.initial(),
    );
  }

  void updateSourceUrl(String value) {
    state = state.copyWith(
      sourceUrl: value,
      sourceValidated: false,
      preflightSummary: const DesktopPreflightSummary.initial(),
    );
  }

  void updateTargetUrl(String value) {
    state = state.copyWith(
      targetUrl: value,
      targetValidated: false,
      preflightSummary: const DesktopPreflightSummary.initial(),
    );
  }

  void updateSourceToken(String value) {
    state = state.copyWith(sourceToken: value, preflightSummary: const DesktopPreflightSummary.initial());
  }

  void updateTargetToken(String value) {
    state = state.copyWith(targetToken: value, preflightSummary: const DesktopPreflightSummary.initial());
  }

  void validateConnections() {
    state = state.copyWith(
      sourceValidated: state.sourceUrl.trim().isNotEmpty,
      targetValidated: state.targetUrl.trim().isNotEmpty,
    );
  }

  void goToStep(int step) {
    state = state.copyWith(step: step.clamp(1, 3));
  }

  Future<void> reviewPreflight(DesktopRunController runController) async {
    final DesktopPreflightSummary summary = await runController.evaluatePreflight(state.toPreflightRequest());
    state = state.copyWith(preflightSummary: summary, step: 3);
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
    state = state.copyWith(settingsProfile: value, preflightSummary: const DesktopPreflightSummary.initial());
  }

  void updateFromTag(String value) {
    state = state.copyWith(fromTag: value);
  }

  void updateToTag(String value) {
    state = state.copyWith(toTag: value);
  }
}
