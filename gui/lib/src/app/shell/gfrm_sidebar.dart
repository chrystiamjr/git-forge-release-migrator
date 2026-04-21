import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/navigation/app_routes.dart';
import 'package:gfrm_gui/src/app/shell/gfrm_logo.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_nav_item.dart';
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
              GfrmNavItem(
                route: route,
                active: !settingsActive && activePrimaryRoute == route,
                onPressed: () {
                  context.go(route.path);
                },
              ),
            const Spacer(),
            Divider(color: colors.border),
            GfrmNavItem(
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
