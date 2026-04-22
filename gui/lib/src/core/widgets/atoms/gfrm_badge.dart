import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmBadge extends StatelessWidget {
  const GfrmBadge({required this.label, required this.backgroundColor, required this.textColor, super.key});

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: unit.s3, vertical: unit.s1),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(unit.s2)),
      child: Text(label, style: GfrmAppTheme.typography.labelMedium.copyWith(color: textColor, letterSpacing: 0)),
    );
  }
}
