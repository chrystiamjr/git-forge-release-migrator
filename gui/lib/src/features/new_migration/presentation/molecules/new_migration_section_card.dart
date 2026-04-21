import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class NewMigrationSectionCard extends StatelessWidget {
  const NewMigrationSectionCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;

    return Container(
      padding: EdgeInsets.all(unit.s6),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(unit.s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          SizedBox(height: unit.s4),
          child,
        ],
      ),
    );
  }
}
