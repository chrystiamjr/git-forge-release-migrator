import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_empty_state.dart';
import 'package:gfrm_gui/src/features/progress/presentation/molecules/run_progress_counts.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class RunProgressSummary extends StatelessWidget {
  const RunProgressSummary({required this.snapshot, super.key});

  final DesktopRunSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Status: ${snapshot.lifecycle}', key: const ValueKey<String>('run-progress-lifecycle')),
        Text('Phase: ${snapshot.activePhase}', key: const ValueKey<String>('run-progress-phase')),
        if (snapshot.completionStatus.isNotEmpty) Text('Outcome: ${snapshot.completionStatus}'),
        if (snapshot.latestFailure != null) Text('Failure: ${snapshot.latestFailure!.message}'),
        SizedBox(height: GfrmAppTheme.unit.s4),
        RunProgressCounts(label: 'Tags', counts: snapshot.tagCounts),
        SizedBox(height: GfrmAppTheme.unit.s4),
        RunProgressCounts(label: 'Releases', counts: snapshot.releaseCounts),
        SizedBox(height: GfrmAppTheme.unit.s6),
        if (snapshot.sessionId.isEmpty && snapshot.runId.isEmpty && snapshot.lifecycle == 'idle')
          const GfrmEmptyState(title: 'No active run', description: 'Run progress appears when a migration starts.')
        else if (snapshot.progressItems.isEmpty)
          const Text('Waiting for item updates.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const <DataColumn>[
                DataColumn(label: Text('Kind')),
                DataColumn(label: Text('Tag')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Message')),
              ],
              rows: snapshot.progressItems
                  .map(
                    (item) => DataRow(
                      cells: <DataCell>[
                        DataCell(Text(item.kind)),
                        DataCell(Text(item.tag)),
                        DataCell(Text(item.status)),
                        DataCell(Text(item.message)),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
