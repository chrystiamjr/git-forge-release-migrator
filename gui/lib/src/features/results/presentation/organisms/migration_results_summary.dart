import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_run_failure_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_progress_item.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_empty_state.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_run_counts.dart';
import 'package:gfrm_gui/src/features/results/presentation/molecules/migration_result_artifacts.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class MigrationResultsSummary extends StatelessWidget {
  const MigrationResultsSummary({required this.snapshot, super.key});

  final DesktopRunSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isIdle) {
      return const GfrmEmptyState(
        title: 'No results to display',
        description: 'Migration summaries and artifact paths will appear here after a run finishes.',
      );
    }
    if (!snapshot.isTerminal) {
      return const GfrmEmptyState(
        title: 'Migration in progress',
        description: 'Results will appear when this run finishes. Follow the current run on the Progress screen.',
      );
    }

    final DesktopRunFailureSummary? failure = snapshot.latestFailure;
    final List<DesktopRunProgressItem> failedItems = snapshot.progressItems
        .where((DesktopRunProgressItem item) => item.isFailed)
        .toList();
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Status: ${snapshot.lifecycle}', key: const ValueKey<String>('run-results-lifecycle')),
        if (snapshot.completionStatus.trim().isNotEmpty)
          Text('Outcome: ${snapshot.completionStatus}', key: const ValueKey<String>('run-results-outcome')),
        Text('Phase: ${snapshot.activePhase}'),
        Text('Total tags: ${snapshot.totalTags}'),
        Text('Failed tags: ${snapshot.failedTags}'),
        if (failure != null) ...<Widget>[
          SizedBox(height: GfrmAppTheme.unit.s4),
          Text('Failure details', style: textTheme.titleMedium),
          Text('Code: ${failure.code}'),
          Text('Failure phase: ${failure.phase}'),
          SelectableText(failure.message, key: const ValueKey<String>('run-results-failure')),
        ],
        SizedBox(height: GfrmAppTheme.unit.s4),
        GfrmRunCounts(label: 'Tags', counts: snapshot.tagCounts, keyPrefix: 'run-results'),
        SizedBox(height: GfrmAppTheme.unit.s4),
        GfrmRunCounts(label: 'Releases', counts: snapshot.releaseCounts, keyPrefix: 'run-results'),
        if (failedItems.isNotEmpty) ...<Widget>[
          SizedBox(height: GfrmAppTheme.unit.s4),
          Text('Failed items', style: textTheme.titleMedium),
          for (final DesktopRunProgressItem item in failedItems) ...<Widget>[
            Text('${item.kind}: ${item.tag}'),
            if (item.message.trim().isNotEmpty) SelectableText(item.message),
          ],
        ],
        SizedBox(height: GfrmAppTheme.unit.s6),
        MigrationResultArtifacts(artifacts: snapshot.artifacts),
        if (snapshot.retryCommand.trim().isNotEmpty) ...<Widget>[
          SizedBox(height: GfrmAppTheme.unit.s6),
          Text('Retry from the terminal', style: textTheme.titleMedium),
          const Text('Use the resume command from this run:'),
          SelectableText(snapshot.retryCommand, key: const ValueKey<String>('run-results-retry-command')),
        ],
      ],
    );
  }
}
