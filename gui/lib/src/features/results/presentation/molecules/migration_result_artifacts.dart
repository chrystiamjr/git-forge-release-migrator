import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_artifacts_summary.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class MigrationResultArtifacts extends StatelessWidget {
  const MigrationResultArtifacts({required this.artifacts, super.key});

  final DesktopArtifactsSummary artifacts;

  @override
  Widget build(BuildContext context) {
    final Map<String, String> paths = <String, String>{
      'summary.json': artifacts.summaryPath,
      'failed-tags.txt': artifacts.failedTagsPath,
      'migration-log.jsonl': artifacts.migrationLogPath,
    }..removeWhere((String name, String path) => path.trim().isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Artifacts', style: Theme.of(context).textTheme.titleMedium),
        if (paths.isEmpty)
          const Text('No artifact paths were reported for this run.')
        else ...<Widget>[
          const Text('Paths reported by this run:'),
          for (final MapEntry<String, String> artifact in paths.entries) ...<Widget>[
            SizedBox(height: GfrmAppTheme.unit.s3),
            Text(artifact.key),
            SelectableText(artifact.value, key: ValueKey<String>('run-results-artifact-${artifact.key}')),
          ],
        ],
      ],
    );
  }
}
