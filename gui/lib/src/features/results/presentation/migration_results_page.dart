import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/features/results/presentation/organisms/migration_results_summary.dart';
import 'package:gfrm_gui/src/runtime/run/providers/desktop_run_controller_provider.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class MigrationResultsPage extends ConsumerWidget {
  const MigrationResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DesktopRunSnapshot> updates = ref.watch(desktopRunSnapshotsProvider);
    // Broadcast updates do not replay when navigating to a finished run.
    final DesktopRunSnapshot snapshot = ref.watch(desktopRunControllerProvider).currentSnapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Results', style: Theme.of(context).textTheme.headlineLarge),
        SizedBox(height: GfrmAppTheme.unit.s6),
        if (updates.hasError)
          const Text('Result updates are unavailable.', key: ValueKey<String>('run-results-stream-error')),
        MigrationResultsSummary(snapshot: snapshot),
      ],
    );
  }
}
