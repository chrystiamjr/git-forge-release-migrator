import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmButton extends StatelessWidget {
  const GfrmButton({required this.label, required this.onPressed, this.icon, super.key});

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final typography = GfrmAppTheme.typography;

    return SizedBox(
      height: 36,
      child: Material(
        color: colors.primary,
        borderRadius: BorderRadius.circular(unit.s2),
        child: InkWell(
          borderRadius: BorderRadius.circular(unit.s2),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: unit.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[Icon(icon, size: 18, color: Colors.white), SizedBox(width: unit.s2)],
                Text(label.toUpperCase(), style: typography.buttonLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
