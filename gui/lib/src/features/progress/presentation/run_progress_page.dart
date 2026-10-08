import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/features/progress/presentation/organisms/run_progress_summary.dart';
import 'package:gfrm_gui/src/runtime/run/providers/desktop_run_controller_provider.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class RunProgressPage extends ConsumerWidget {
  const RunProgressPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DesktopRunSnapshot> updates = ref.watch(desktopRunSnapshotsProvider);
    // Broadcast streams do not replay. Read current state when entering mid-run.
    final DesktopRunSnapshot snapshot = ref.watch(desktopRunControllerProvider).currentSnapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Run Progress', style: Theme.of(context).textTheme.headlineLarge),
        SizedBox(height: GfrmAppTheme.unit.s6),
        if (updates.hasError)
          const Text('Live progress updates are unavailable.', key: ValueKey<String>('run-progress-stream-error')),
        RunProgressSummary(snapshot: snapshot),
      ],
    );
  }
}
