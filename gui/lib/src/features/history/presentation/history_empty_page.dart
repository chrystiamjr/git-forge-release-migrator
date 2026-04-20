import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_empty_state.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class HistoryEmptyPage extends StatelessWidget {
  const HistoryEmptyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('History', style: Theme.of(context).textTheme.headlineLarge),
        SizedBox(height: unit.s6),
        const GfrmEmptyState(
          title: 'No migration history',
          description: 'Completed and resumed migrations will appear here once you run them.',
        ),
      ],
    );
  }
}
