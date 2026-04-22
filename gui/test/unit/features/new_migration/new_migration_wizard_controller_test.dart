import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_gui/src/application/run/contracts/desktop_run_controller.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_check_item.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_action_result.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_controller.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
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

    test('maps wizard state to DesktopPreflightRequest', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final NewMigrationWizardController controller = container.read(newMigrationWizardProvider.notifier);

      controller.selectSourceProvider(MigrationProviderOption.github);
      controller.selectTargetProvider(MigrationProviderOption.gitlab);
      controller.updateSourceUrl(' https://github.com/acme/source ');
      controller.updateTargetUrl(' https://gitlab.com/acme/target ');
      controller.updateSourceToken(' source-token ');
      controller.updateTargetToken(' target-token ');
      controller.updateSettingsProfile(' release ');

      final request = container.read(newMigrationWizardProvider).toPreflightRequest();

      expect(request.sourceProvider, 'github');
      expect(request.targetProvider, 'gitlab');
      expect(request.sourceUrl, 'https://github.com/acme/source');
      expect(request.targetUrl, 'https://gitlab.com/acme/target');
      expect(request.sourceToken, 'source-token');
      expect(request.targetToken, 'target-token');
      expect(request.settingsProfile, 'release');
    });

    test('blocking preflight errors disable migration start while warnings allow it', () {
      final DesktopPreflightSummary blocked = DesktopPreflightSummary(
        status: 'failed',
        checks: const <DesktopPreflightCheckItem>[
          DesktopPreflightCheckItem(code: 'source', message: 'Missing source token.', status: 'error'),
        ],
        checkCount: 1,
        blockingCount: 1,
        warningCount: 0,
      );
      final DesktopPreflightSummary warningOnly = DesktopPreflightSummary(
        status: 'warning',
        checks: const <DesktopPreflightCheckItem>[
          DesktopPreflightCheckItem(code: 'profile', message: 'Profile missing.', status: 'warning'),
        ],
        checkCount: 1,
        blockingCount: 0,
        warningCount: 1,
      );

      expect(NewMigrationWizardState(preflightSummary: blocked).canStartMigration, isFalse);
      expect(NewMigrationWizardState(preflightSummary: warningOnly).canStartMigration, isTrue);
    });

    test('moves to step three with blocking preflight summary when evaluation throws', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final NewMigrationWizardController controller = container.read(newMigrationWizardProvider.notifier);

      await controller.reviewPreflight(_ThrowingDesktopRunController());

      final NewMigrationWizardState state = container.read(newMigrationWizardProvider);
      expect(state.step, 3);
      expect(state.preflightSummary.status, 'failed');
      expect(state.preflightSummary.blockingCount, 1);
      expect(state.preflightSummary.checks.single.code, 'preflight_exception');
    });
  });
}

final class _ThrowingDesktopRunController implements DesktopRunController {
  @override
  DesktopRunSnapshot get currentSnapshot => const DesktopRunSnapshot.initial();

  @override
  Stream<DesktopRunSnapshot> get snapshots => const Stream<DesktopRunSnapshot>.empty();

  @override
  Future<DesktopPreflightSummary> evaluatePreflight(DesktopPreflightRequest request) {
    throw StateError('preflight failed');
  }

  @override
  Future<DesktopRunSession> startRun(DesktopRunStartRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<DesktopRunSession> resumeRun(DesktopRunResumeRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<DesktopRunActionResult> cancelActiveRun() {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
