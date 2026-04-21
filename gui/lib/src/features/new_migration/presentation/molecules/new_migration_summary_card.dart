import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class NewMigrationSummaryCard extends StatelessWidget {
  const NewMigrationSummaryCard({required this.state, super.key});

  final NewMigrationWizardState state;

  @override
  Widget build(BuildContext context) {
    final GfrmColors colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;

    return Container(
      padding: EdgeInsets.all(unit.s6),
      decoration: BoxDecoration(color: colors.surfaceStrong, borderRadius: BorderRadius.circular(unit.s3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Migration Summary', style: Theme.of(context).textTheme.headlineSmall),
          SizedBox(height: unit.s4),
          _summaryRow(
            icon: Icons.cloud_outlined,
            label: 'Source',
            value: '${state.sourceProvider.label}  ${state.sourceUrl.trim()}',
          ),
          _summaryRow(
            icon: Icons.outbox_outlined,
            label: 'Target',
            value: '${state.targetProvider.label}  ${state.targetUrl.trim()}',
          ),
          _summaryRow(
            icon: Icons.sell_outlined,
            label: 'Tags',
            value: state.migrateTags ? '${state.selectedTagCount} selected' : 'Skipped',
          ),
          _summaryRow(
            icon: Icons.local_offer_outlined,
            label: 'Releases',
            value: _includedLabel(state.migrateReleases),
          ),
          _summaryRow(
            icon: Icons.inventory_2_outlined,
            label: 'Assets',
            value: _includedLabel(state.migrateReleaseAssets),
          ),
          _summaryRow(
            icon: Icons.play_circle_outline,
            label: 'Mode',
            value: state.dryRun ? 'Dry Run' : 'Live',
            valueColor: state.dryRun ? GfrmAppTheme.colors.warning : colors.success,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow({required IconData icon, required String label, required String value, Color? valueColor}) {
    final GfrmColors colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;

    return Padding(
      padding: EdgeInsets.only(bottom: unit.s3),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colors.textSecondary),
          SizedBox(width: unit.s3),
          SizedBox(
            width: 72,
            child: Text(label, style: GfrmAppTheme.typography.labelMedium.copyWith(letterSpacing: 0)),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GfrmAppTheme.typography.bodyMedium.copyWith(color: valueColor ?? colors.textBody),
            ),
          ),
        ],
      ),
    );
  }

  String _includedLabel(bool isIncluded) {
    return isIncluded ? 'Included' : 'Excluded';
  }
}
