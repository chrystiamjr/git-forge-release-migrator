import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/app_routes.dart';
import 'package:gfrm_gui/src/app/gfrm_logo.dart';
import 'package:gfrm_gui/src/theme/gfrm_colors.dart';

class GfrmSidebar extends StatelessWidget {
  const GfrmSidebar({required this.currentLocation, super.key});

  final String currentLocation;

  @override
  Widget build(BuildContext context) {
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final AppRoute? activePrimaryRoute = AppRoute.activePrimaryRouteFor(currentLocation);
    final bool settingsActive = AppRoute.isSettingsLocation(currentLocation);

    return ColoredBox(
      color: GfrmColors.sidebarBackground,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, isMacOS ? 56 : 24, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const GfrmLogo(),
            const SizedBox(height: 32),
            for (final AppRoute route in AppRoute.primaryRoutes)
              _GfrmSidebarItem(
                route: route,
                active: !settingsActive && activePrimaryRoute == route,
                onPressed: () {
                  context.go(route.path);
                },
              ),
            const Spacer(),
            const Divider(color: GfrmColors.border),
            _GfrmSidebarItem(
              route: AppRoute.settings,
              active: settingsActive,
              onPressed: () {
                context.go(AppRoute.settings.path);
              },
            ),
            const SizedBox(height: 12),
            Text(
              'devuser',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: GfrmColors.textMuted, letterSpacing: 0),
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
    final Color textColor = active ? GfrmColors.accent : GfrmColors.textMuted;

    return Container(
      height: _height,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: active ? GfrmColors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: active ? const Border(left: BorderSide(color: GfrmColors.accent, width: 3)) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Row(
              children: <Widget>[
                Icon(route.icon, size: 20, color: textColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    route.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'IBMPlexSans',
                      fontSize: 14,
                      color: GfrmColors.textMuted,
                      fontVariations: <FontVariation>[FontVariation('wght', 500)],
                    ).copyWith(color: textColor),
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
