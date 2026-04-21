import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_controller.dart';
import 'package:gfrm_gui/src/features/new_migration/domain/migration_provider_option.dart';

void main() {
  group('NewMigrationWizardController', () {
    test('blocks step one until both repository URLs are validated', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final NewMigrationWizardController controller = container.read(newMigrationWizardProvider.notifier);

      expect(container.read(newMigrationWizardProvider).canContinueFromStepOne, isFalse);

      controller.updateSourceUrl('https://github.com/org/source');
      controller.updateTargetUrl('https://gitlab.com/org/target');
      controller.validateConnections();

      expect(container.read(newMigrationWizardProvider).canContinueFromStepOne, isTrue);
    });

    test('updates matching tag preview from semver range', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final NewMigrationWizardController controller = container.read(newMigrationWizardProvider.notifier);

      controller.updateFromTag('v2.0.1');
      controller.updateToTag('v2.1.0');

      expect(container.read(newMigrationWizardProvider).matchingTags, <String>['v2.1.0', 'v2.0.1']);
    });

    test('blocks invalid semver range from matching tag preview and request mapping', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final NewMigrationWizardController controller = container.read(newMigrationWizardProvider.notifier);

      controller.updateFromTag('v2');

      expect(container.read(newMigrationWizardProvider).matchingTags, isEmpty);
      expect(container.read(newMigrationWizardProvider).toRunStartRequest, throwsArgumentError);
    });

    test('maps wizard state to DesktopRunStartRequest', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final NewMigrationWizardController controller = container.read(newMigrationWizardProvider.notifier);

      controller.selectSourceProvider(MigrationProviderOption.bitbucket);
      controller.selectTargetProvider(MigrationProviderOption.github);
      controller.updateSourceUrl(' https://bitbucket.org/acme/source ');
      controller.updateTargetUrl(' https://github.com/acme/target ');
      controller.updateSourceToken(' source-token ');
      controller.updateTargetToken(' target-token ');
      controller.setMigrateTags(false);
      controller.setMigrateReleases(false);
      controller.setMigrateReleaseAssets(false);
      controller.setDryRun(false);
      controller.updateSettingsProfile(' release ');
      controller.updateFromTag(' v1.0.0 ');
      controller.updateToTag(' v1.9.0 ');

      final request = container.read(newMigrationWizardProvider).toRunStartRequest();

      expect(request.sourceProvider, 'bitbucket');
      expect(request.targetProvider, 'github');
      expect(request.sourceUrl, 'https://bitbucket.org/acme/source');
      expect(request.targetUrl, 'https://github.com/acme/target');
      expect(request.sourceToken, 'source-token');
      expect(request.targetToken, 'target-token');
      expect(request.skipTagMigration, isTrue);
      expect(request.skipReleaseMigration, isTrue);
      expect(request.skipReleaseAssetMigration, isTrue);
      expect(request.dryRun, isFalse);
      expect(request.settingsProfile, 'release');
      expect(request.fromTag, 'v1.0.0');
      expect(request.toTag, 'v1.9.0');
    });
  });
}
