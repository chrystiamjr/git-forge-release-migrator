import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/core/widgets/atoms/gfrm_button.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_controller.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_preflight_results_card.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_summary_card.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class NewMigrationPreflightStep extends StatelessWidget {
  const NewMigrationPreflightStep({required this.state, required this.controller, super.key});

  final NewMigrationWizardState state;
  final NewMigrationWizardController controller;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NewMigrationPreflightResultsCard(state: state),
        SizedBox(height: unit.s6),
        NewMigrationSummaryCard(state: state),
        SizedBox(height: unit.s6),
        Row(
          children: <Widget>[
            GfrmButton(
              label: 'Back',
              icon: Icons.arrow_back,
              isSecondary: true,
              height: 40,
              onPressed: () => controller.goToStep(2),
            ),
            SizedBox(width: unit.s3),
            GfrmButton(label: 'Start Migration', icon: Icons.play_arrow, isSuccess: true, height: 40, onPressed: null),
          ],
        ),
      ],
    );
  }
}
