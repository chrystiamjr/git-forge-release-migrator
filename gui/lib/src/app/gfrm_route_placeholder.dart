import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_colors.dart';

class GfrmRoutePlaceholder extends StatelessWidget {
  const GfrmRoutePlaceholder({required this.title, required this.description, super.key});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: GfrmColors.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GfrmColors.border),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: GfrmColors.textSecondary)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
