import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_preflight_check_item.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_blocking_error_banner.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_preflight_check_row.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_section_card.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class NewMigrationPreflightResultsCard extends StatelessWidget {
  const NewMigrationPreflightResultsCard({required this.state, super.key});

  final NewMigrationWizardState state;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return NewMigrationSectionCard(
      title: 'Preflight Results',
      child: Column(
        children: <Widget>[
          if (state.preflightSummary.hasBlockingErrors) ...<Widget>[
            NewMigrationBlockingErrorBanner(blockingCount: state.preflightSummary.blockingCount),
            SizedBox(height: unit.s4),
          ],
          for (final DesktopPreflightCheckItem item in state.preflightSummary.checks) ...<Widget>[
            NewMigrationPreflightCheckRow(item: item, hasBlockingErrors: state.preflightSummary.hasBlockingErrors),
            if (item != state.preflightSummary.checks.last) SizedBox(height: unit.s3),
          ],
        ],
      ),
    );
  }
}
