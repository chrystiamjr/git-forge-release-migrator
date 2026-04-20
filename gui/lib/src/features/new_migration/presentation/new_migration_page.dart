import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_controller.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/organisms/new_migration_options_step.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/organisms/new_migration_source_target_step.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class NewMigrationPage extends ConsumerWidget {
  const NewMigrationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NewMigrationWizardState state = ref.watch(newMigrationWizardProvider);
    final NewMigrationWizardController controller = ref.read(newMigrationWizardProvider.notifier);
    final unit = GfrmAppTheme.unit;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('New Migration', style: Theme.of(context).textTheme.headlineLarge),
          SizedBox(height: unit.s2),
          Text('Step ${state.step} of 2', style: Theme.of(context).textTheme.bodyMedium),
          SizedBox(height: unit.s6),
          if (state.step == 1) NewMigrationSourceTargetStep(state: state, controller: controller),
          if (state.step == 2) NewMigrationOptionsStep(state: state, controller: controller),
        ],
      ),
    );
  }
}
