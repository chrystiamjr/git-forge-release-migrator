import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/core/widgets/atoms/gfrm_button.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_controller.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/matching_tags_preview_section.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/migration_option_toggle.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_section_card.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class NewMigrationOptionsStep extends StatelessWidget {
  const NewMigrationOptionsStep({required this.state, required this.controller, super.key});

  final NewMigrationWizardState state;
  final NewMigrationWizardController controller;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NewMigrationSectionCard(
          title: 'Options and filters',
          child: Column(
            children: <Widget>[
              MigrationOptionToggle(
                key: const ValueKey<String>('new-migration-migrate-tags'),
                title: 'Migrate tags',
                value: state.migrateTags,
                onChanged: controller.setMigrateTags,
              ),
              MigrationOptionToggle(
                key: const ValueKey<String>('new-migration-migrate-releases'),
                title: 'Migrate releases',
                value: state.migrateReleases,
                onChanged: controller.setMigrateReleases,
              ),
              MigrationOptionToggle(
                key: const ValueKey<String>('new-migration-migrate-assets'),
                title: 'Migrate release assets',
                value: state.migrateReleaseAssets,
                onChanged: controller.setMigrateReleaseAssets,
              ),
              MigrationOptionToggle(
                key: const ValueKey<String>('new-migration-dry-run'),
                title: 'Dry run',
                value: state.dryRun,
                onChanged: controller.setDryRun,
              ),
              SizedBox(height: unit.s4),
              TextFormField(
                key: const ValueKey<String>('new-migration-settings-profile'),
                initialValue: state.settingsProfile,
                decoration: const InputDecoration(labelText: 'Settings profile'),
                onChanged: controller.updateSettingsProfile,
              ),
              SizedBox(height: unit.s4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey<String>('new-migration-include-pattern'),
                      initialValue: state.includePattern,
                      decoration: const InputDecoration(labelText: 'Include tags'),
                      onChanged: controller.updateIncludePattern,
                    ),
                  ),
                  SizedBox(width: unit.s4),
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey<String>('new-migration-exclude-pattern'),
                      initialValue: state.excludePattern,
                      decoration: const InputDecoration(labelText: 'Exclude tags'),
                      onChanged: controller.updateExcludePattern,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: unit.s6),
        MatchingTagsPreviewSection(tags: state.matchingTags),
        SizedBox(height: unit.s6),
        Text('RunRequest preview', style: Theme.of(context).textTheme.headlineSmall),
        SizedBox(height: unit.s2),
        Text(
          '${state.sourceProvider.id} -> ${state.targetProvider.id} | profile ${state.settingsProfile} | dry run ${state.dryRun}',
          style: GfrmAppTheme.typography.mono,
        ),
        SizedBox(height: unit.s6),
        Row(
          children: <Widget>[
            GfrmButton(
              label: 'Back',
              icon: Icons.arrow_back,
              isSecondary: true,
              onPressed: () => controller.goToStep(1),
            ),
            SizedBox(width: unit.s3),
            GfrmButton(label: 'Review request', icon: Icons.fact_check_outlined, onPressed: () {}),
          ],
        ),
      ],
    );
  }
}
