import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_run_count_summary.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_stat_card.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmRunCounts extends StatelessWidget {
  const GfrmRunCounts({required this.label, required this.counts, required this.keyPrefix, super.key});

  final String label;
  final DesktopRunCountSummary counts;
  final String keyPrefix;
  static const double _cardWidth = 200;

  @override
  Widget build(BuildContext context) {
    final Map<String, int> values = <String, int>{
      'created': counts.created,
      'would create': counts.wouldCreate,
      'skipped existing': counts.skippedExisting,
      'failed': counts.failed,
    };

    return Wrap(
      spacing: GfrmAppTheme.unit.s4,
      runSpacing: GfrmAppTheme.unit.s4,
      children: values.entries
          .map(
            (entry) => SizedBox(
              width: _cardWidth,
              child: GfrmStatCard(
                key: ValueKey<String>('$keyPrefix-${label.toLowerCase()}-${entry.key}'),
                label: '$label ${entry.key}',
                value: '${entry.value}',
              ),
            ),
          )
          .toList(),
    );
  }
}
