import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_empty_state.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class ResultsEmptyPage extends StatelessWidget {
  const ResultsEmptyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Results', style: Theme.of(context).textTheme.headlineLarge),
        SizedBox(height: unit.s6),
        const GfrmEmptyState(
          title: 'No results to display',
          description: 'Migration summaries and artifact shortcuts will appear here after a run finishes.',
        ),
      ],
    );
  }
}
