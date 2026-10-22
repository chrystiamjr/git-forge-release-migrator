import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/features/results/presentation/migration_results_page.dart';
import 'package:gfrm_gui/src/features/results/presentation/organisms/migration_results_summary.dart';
import 'package:gfrm_gui/src/runtime/run/providers/desktop_run_controller_provider.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class MigrationResultsPageState extends ConsumerState<MigrationResultsPage> {
  bool _isRetrying = false;
  String? _retryError;

  Future<void> _retryFailedTags() async {
    if (_isRetrying) {
      return;
    }
    setState(() {
      _isRetrying = true;
      _retryError = null;
    });
    try {
      final DesktopRunSession session = await ref.read(desktopRunControllerProvider).retryFailedTags();
      await session.completion;
    } catch (_) {
      if (mounted) {
        setState(() => _retryError = 'Retry could not start or finish. Check the current results and retry files.');
      }
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        if (_retryError != null) Text(_retryError!, key: const ValueKey<String>('run-results-retry-error')),
        MigrationResultsSummary(snapshot: snapshot, onRetryFailedTags: _retryFailedTags, isRetrying: _isRetrying),
      ],
    );
  }
}
