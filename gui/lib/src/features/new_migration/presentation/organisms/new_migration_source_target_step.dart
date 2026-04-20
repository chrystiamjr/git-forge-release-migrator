import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/core/widgets/atoms/gfrm_button.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_controller.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/migration_endpoint_section.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class NewMigrationSourceTargetStep extends StatelessWidget {
  const NewMigrationSourceTargetStep({required this.state, required this.controller, super.key});

  final NewMigrationWizardState state;
  final NewMigrationWizardController controller;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: MigrationEndpointSection(
                title: 'Source repository',
                selectedProvider: state.sourceProvider,
                urlKey: const ValueKey<String>('new-migration-source-url'),
                tokenKey: const ValueKey<String>('new-migration-source-token'),
                url: state.sourceUrl,
                token: state.sourceToken,
                isValidated: state.sourceValidated,
                onProviderChanged: controller.selectSourceProvider,
                onUrlChanged: controller.updateSourceUrl,
                onTokenChanged: controller.updateSourceToken,
              ),
            ),
            SizedBox(width: unit.s6),
            Expanded(
              child: MigrationEndpointSection(
                title: 'Target repository',
                selectedProvider: state.targetProvider,
                urlKey: const ValueKey<String>('new-migration-target-url'),
                tokenKey: const ValueKey<String>('new-migration-target-token'),
                url: state.targetUrl,
                token: state.targetToken,
                isValidated: state.targetValidated,
                onProviderChanged: controller.selectTargetProvider,
                onUrlChanged: controller.updateTargetUrl,
                onTokenChanged: controller.updateTargetToken,
              ),
            ),
          ],
        ),
        SizedBox(height: unit.s6),
        Row(
          children: <Widget>[
            GfrmButton(
              label: 'Validate connections',
              icon: Icons.verified_outlined,
              onPressed: state.canValidateConnections ? controller.validateConnections : null,
            ),
            SizedBox(width: unit.s3),
            GfrmButton(
              label: 'Next',
              icon: Icons.arrow_forward,
              onPressed: state.canContinueFromStepOne ? () => controller.goToStep(2) : null,
            ),
          ],
        ),
      ],
    );
  }
}
