# Desktop shell
Fixed 220px sidebar; constrained 1120px content; macOS titlebar padding 56px.

## gfrm_logo
Source: `gui/lib/src/app/shell/gfrm_logo.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmLogo extends StatelessWidget {
  const GfrmLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;

    return Row(
      children: <Widget>[
        SvgPicture.asset(
          '../website/static/img/logo.svg',
          width: 92,
          height: 42,
          colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
          semanticsLabel: 'gfrm',
        ),
      ],
    );
  }
}

```

## gfrm_shell_page
Source: `gui/lib/src/app/shell/gfrm_shell_page.dart`

```dart
import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/app/shell/gfrm_sidebar.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmShellPage extends StatelessWidget {
  const GfrmShellPage({required this.currentLocation, required this.child, super.key});

  static const Key sidebarKey = Key('gfrm-sidebar');
  static const Key contentKey = Key('gfrm-content');
  static const double _sidebarWidth = 220;

  final String currentLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    return Scaffold(
      body: Row(
        children: <Widget>[
          SizedBox(
            key: sidebarKey,
            width: _sidebarWidth,
            child: GfrmSidebar(currentLocation: currentLocation),
          ),
          Expanded(
            child: ColoredBox(
              key: contentKey,
              color: colors.surface,
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(unit.s6, isMacOS ? unit.s14 : unit.s6, unit.s6, unit.s8),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

```

## gfrm_sidebar
Source: `gui/lib/src/app/shell/gfrm_sidebar.dart`

```dart
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

```

## gfrm_app
Source: `gui/lib/src/app/gfrm_app.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/navigation/app_router.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmApp extends ConsumerWidget {
  const GfrmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter routerConfig = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'gfrm',
      debugShowCheckedModeBanner: false,
      theme: GfrmAppTheme.themeData,
      routerConfig: routerConfig,
    );
  }
}

```