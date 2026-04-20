import 'package:flutter/material.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmRoutePlaceholder extends StatelessWidget {
  const GfrmRoutePlaceholder({required this.title, required this.description, super.key});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final shadows = GfrmAppTheme.shadows;

    return Container(
      margin: EdgeInsets.only(bottom: unit.s1),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: EdgeInsets.all(unit.s6),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(unit.s5),
        border: Border.all(color: colors.border),
        boxShadow: <BoxShadow>[shadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
          SizedBox(height: unit.s2),
          Text(description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.textSecondary)),
          SizedBox(height: unit.s2),
        ],
      ),
    );
  }
}
