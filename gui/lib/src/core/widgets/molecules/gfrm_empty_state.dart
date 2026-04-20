import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmEmptyState extends StatelessWidget {
  const GfrmEmptyState({required this.title, required this.description, this.action, super.key});

  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final shadows = GfrmAppTheme.shadows;
    final typography = GfrmAppTheme.typography;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(unit.s6, unit.s10, unit.s6, unit.s14),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(unit.s5),
        border: Border.all(color: colors.border),
        boxShadow: <BoxShadow>[shadows.card],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SvgPicture.asset('../website/static/img/gfrm_nodes.svg', height: 130, semanticsLabel: 'empty nodes'),
          SizedBox(height: unit.s6),
          Text(title, textAlign: TextAlign.center, style: typography.emptyStateTitle),
          SizedBox(height: unit.s2),
          Text(description, textAlign: TextAlign.center, style: typography.emptyStateDescription),
          if (action != null) ...<Widget>[SizedBox(height: unit.s8), action!],
        ],
      ),
    );
  }
}
