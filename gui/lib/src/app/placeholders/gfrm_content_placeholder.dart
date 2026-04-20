import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/runtime/gfrm_runtime_contract_summary.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmContentPlaceholder extends StatelessWidget {
  const GfrmContentPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final typography = GfrmAppTheme.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Desktop scaffold ready', style: Theme.of(context).textTheme.headlineLarge),
        SizedBox(height: unit.s2),
        Text(
          'Workspace locked at gui/, desktop targets enabled, and shell ready for route work.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
        ),
        SizedBox(height: unit.s6),
        Wrap(
          spacing: unit.s4,
          runSpacing: unit.s4,
          children: <Widget>[
            _card(
              title: 'Shared runtime contracts',
              lines: <String>[
                'RunState lifecycle: ${GfrmRuntimeContractSummary.lifecycleLabel}',
                'RunState phase: ${GfrmRuntimeContractSummary.phaseLabel}',
                '${GfrmRuntimeContractSummary.lifecycleCount} lifecycle states and ${GfrmRuntimeContractSummary.phaseCount} phases available from dart_cli.',
              ],
            ),
            _card(
              title: 'Desktop targets',
              lines: const <String>[
                'macOS title bar blends into sidebar.',
                'Windows default window starts at 1280x800.',
                'Linux shell starts at 1280x800.',
              ],
            ),
            _card(
              title: 'Fonts and layout',
              lines: const <String>[
                'IBM Plex Sans drives UI text.',
                'IBM Plex Mono is ready for logs and artifacts.',
                'Inter is reserved for gfrm wordmark.',
              ],
            ),
          ],
        ),
        SizedBox(height: unit.s6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 200),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(unit.s5),
            border: Border.all(color: colors.border),
          ),
          padding: EdgeInsets.all(unit.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Content area placeholder', style: Theme.of(context).textTheme.headlineSmall),
              SizedBox(height: unit.s3),
              Text(
                'Future tickets can mount dashboard, wizard, progress, results, history, and settings inside this scrollable surface without changing the shell contract.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: unit.s6),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(unit.s4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(unit.s3),
                  border: Border.all(color: colors.border),
                ),
                child: Text('migration-results/<timestamp>/summary.json', style: typography.mono),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _card({required String title, required List<String> lines}) {
  final colors = GfrmAppTheme.colors;
  final unit = GfrmAppTheme.unit;
  final shadows = GfrmAppTheme.shadows;
  final typography = GfrmAppTheme.typography;

  return Container(
    width: 320,
    padding: EdgeInsets.all(unit.s4),
    decoration: BoxDecoration(
      color: colors.surfaceCard,
      borderRadius: BorderRadius.circular(unit.s5),
      border: Border.all(color: colors.border),
      boxShadow: <BoxShadow>[shadows.card],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: typography.cardTitle),
        SizedBox(height: unit.s3),
        for (final String line in lines) ...<Widget>[Text(line, style: typography.cardBody), SizedBox(height: unit.s2)],
        SizedBox(height: unit.s1),
      ],
    ),
  );
}
