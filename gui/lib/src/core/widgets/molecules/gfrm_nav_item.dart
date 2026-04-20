import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/app/navigation/app_routes.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmNavItem extends StatelessWidget {
  const GfrmNavItem({required this.route, required this.active, required this.onPressed, super.key});

  static const double _height = 40;

  final AppRoute route;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final typography = GfrmAppTheme.typography;
    final Color textColor = active ? colors.accent : colors.textMuted;

    return Container(
      height: _height,
      margin: EdgeInsets.only(bottom: unit.s2),
      decoration: BoxDecoration(
        color: active ? colors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(unit.s2),
        border: active ? Border(left: BorderSide(color: colors.accent, width: 3)) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(unit.s2),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.only(left: unit.s4, right: unit.s3),
            child: Row(
              children: <Widget>[
                Icon(route.icon, size: 20, color: textColor),
                SizedBox(width: unit.s3),
                Expanded(
                  child: Text(
                    route.label,
                    overflow: TextOverflow.ellipsis,
                    style: typography.sidebarItem.copyWith(color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
