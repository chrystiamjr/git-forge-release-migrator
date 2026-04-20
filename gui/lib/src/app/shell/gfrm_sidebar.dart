import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/navigation/app_routes.dart';
import 'package:gfrm_gui/src/app/shell/gfrm_logo.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmSidebar extends StatelessWidget {
  const GfrmSidebar({required this.currentLocation, super.key});

  final String currentLocation;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final AppRoute? activePrimaryRoute = AppRoute.activePrimaryRouteFor(currentLocation);
    final bool settingsActive = AppRoute.isSettingsLocation(currentLocation);

    return ColoredBox(
      color: colors.sidebarBackground,
      child: Padding(
        padding: EdgeInsets.fromLTRB(unit.s4, isMacOS ? unit.s14 : unit.s6, unit.s4, unit.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const GfrmLogo(),
            SizedBox(height: unit.s8),
            for (final AppRoute route in AppRoute.primaryRoutes)
              _GfrmSidebarItem(
                route: route,
                active: !settingsActive && activePrimaryRoute == route,
                onPressed: () {
                  context.go(route.path);
                },
              ),
            const Spacer(),
            Divider(color: colors.border),
            _GfrmSidebarItem(
              route: AppRoute.settings,
              active: settingsActive,
              onPressed: () {
                context.go(AppRoute.settings.path);
              },
            ),
            SizedBox(height: unit.s3),
            Text(
              'devuser',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.textMuted, letterSpacing: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _GfrmSidebarItem extends StatelessWidget {
  const _GfrmSidebarItem({required this.route, required this.active, required this.onPressed});

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
