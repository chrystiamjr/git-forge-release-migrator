import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmButton extends StatelessWidget {
  const GfrmButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isSecondary = false,
    this.isSuccess = false,
    this.height = 36,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isSecondary;
  final bool isSuccess;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final typography = GfrmAppTheme.typography;

    return SizedBox(
      height: height,
      child: Material(
        color: _backgroundColor(),
        borderRadius: BorderRadius.circular(unit.s2),
        child: InkWell(
          borderRadius: BorderRadius.circular(unit.s2),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: unit.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: isSecondary ? colors.textBody : Colors.white),
                  SizedBox(width: unit.s2),
                ],
                Text(label.toUpperCase(), style: typography.buttonLabel.copyWith(color: _foregroundColor())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor() {
    final colors = GfrmAppTheme.colors;
    if (onPressed == null) {
      return colors.illustrationStroke;
    }
    if (isSecondary) {
      return colors.surface;
    }
    if (isSuccess) {
      return colors.success;
    }
    return colors.primary;
  }

  Color _foregroundColor() {
    if (isSecondary) {
      return GfrmAppTheme.colors.textBody;
    }
    return Colors.white;
  }
}
