import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/runtime/gfrm_runtime_contract_summary.dart';
import 'package:gfrm_gui/src/theme/gfrm_colors.dart';
import 'package:gfrm_gui/src/theme/gfrm_typography.dart';

class GfrmContentPlaceholder extends StatelessWidget {
  const GfrmContentPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Desktop scaffold ready', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text(
          'Workspace locked at gui/, desktop targets enabled, and shell ready for route work.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: GfrmColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
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
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 200),
          decoration: BoxDecoration(
            color: GfrmColors.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: GfrmColors.border),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Content area placeholder', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                'Future tickets can mount dashboard, wizard, progress, results, history, and settings inside this scrollable surface without changing the shell contract.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GfrmColors.border),
                ),
                child: const Text('migration-results/<timestamp>/summary.json', style: GfrmTypography.mono),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _card({required String title, required List<String> lines}) {
  return Container(
    width: 320,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: GfrmColors.surfaceCard,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: GfrmColors.border),
      boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'IBMPlexSans',
            fontSize: 16,
            color: GfrmColors.textHeading,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final String line in lines) ...<Widget>[
          Text(
            line,
            style: const TextStyle(fontFamily: 'IBMPlexSans', fontSize: 14, color: GfrmColors.textBody),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
      ],
    ),
  );
}
