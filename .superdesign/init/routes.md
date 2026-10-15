# Desktop routes
Dashboard, New Migration, Run Progress, Results, History, Settings (credentials/profiles/general). Results/history/settings are scaffolds.

## app_routes
Source: `gui/lib/src/app/navigation/app_routes.dart`

```dart
import 'package:flutter/material.dart';

enum AppRoute {
  dashboard('/dashboard', 'Dashboard', Icons.dashboard_outlined),
  newMigration('/new-migration', 'New Migration', Icons.add_box_outlined),
  progress('/progress', 'Run Progress', Icons.sync_outlined),
  results('/results', 'Results', Icons.task_alt_outlined),
  history('/history', 'History', Icons.history),
  settings('/settings', 'Settings', Icons.settings_outlined),
  settingsCredentials('/settings/credentials', 'Credentials', Icons.key_outlined),
  settingsProfiles('/settings/profiles', 'Profiles', Icons.badge_outlined),
  settingsGeneral('/settings/general', 'General', Icons.tune_outlined);

  const AppRoute(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;

  static const List<AppRoute> primaryRoutes = <AppRoute>[dashboard, newMigration, progress, results, history];

  static const List<AppRoute> settingsRoutes = <AppRoute>[
    settings,
    settingsCredentials,
    settingsProfiles,
    settingsGeneral,
  ];

  static AppRoute? activePrimaryRouteFor(String location) {
    for (final AppRoute route in primaryRoutes) {
      if (location == route.path || location.startsWith('${route.path}/')) {
        return route;
      }
    }

    return null;
  }

  static bool isSettingsLocation(String location) {
    return location == settings.path || location.startsWith('${settings.path}/');
  }
}

```

## app_router
Source: `gui/lib/src/app/navigation/app_router.dart`

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gfrm_gui/src/app/placeholders/gfrm_route_placeholder.dart';
import 'package:gfrm_gui/src/app/shell/gfrm_shell_page.dart';
import 'package:gfrm_gui/src/features/dashboard/presentation/dashboard_empty_page.dart';
import 'package:gfrm_gui/src/features/history/presentation/history_empty_page.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/new_migration_page.dart';
import 'package:gfrm_gui/src/features/results/presentation/results_empty_page.dart';
import 'package:gfrm_gui/src/features/progress/presentation/run_progress_page.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_routes.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final GoRouter router = GoRouter(
    initialLocation: AppRoute.dashboard.path,
    redirect: (BuildContext context, GoRouterState state) {
      if (state.uri.path == '/') {
        return AppRoute.dashboard.path;
      }

      return null;
    },
    routes: <RouteBase>[
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return GfrmShellPage(currentLocation: state.uri.path, child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: AppRoute.dashboard.path,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return _page(const DashboardEmptyPage());
            },
          ),
          GoRoute(
            path: AppRoute.newMigration.path,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return _page(const NewMigrationPage());
            },
          ),
          GoRoute(
            path: AppRoute.progress.path,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return _page(const RunProgressPage());
            },
          ),
          GoRoute(
            path: AppRoute.results.path,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return _page(const ResultsEmptyPage());
            },
          ),
          GoRoute(
            path: AppRoute.history.path,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return _page(const HistoryEmptyPage());
            },
          ),
          GoRoute(
            path: AppRoute.settings.path,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return _page(
                const GfrmRoutePlaceholder(
                  title: 'Settings',
                  description: 'Settings landing page for credentials, profiles, and general preferences.',
                ),
              );
            },
            routes: <RouteBase>[
              GoRoute(
                path: 'credentials',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return _page(
                    const GfrmRoutePlaceholder(
                      title: 'Credential Management',
                      description: 'Profile-scoped provider tokens and credential health checks will mount here.',
                    ),
                  );
                },
              ),
              GoRoute(
                path: 'profiles',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return _page(
                    const GfrmRoutePlaceholder(
                      title: 'Profiles',
                      description: 'Profile creation, editing, defaults, and provider mapping will mount here.',
                    ),
                  );
                },
              ),
              GoRoute(
                path: 'general',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return _page(
                    const GfrmRoutePlaceholder(
                      title: 'General',
                      description: 'App preferences, diagnostics defaults, and layout options will mount here.',
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

Page<void> _page(Widget child) {
  return NoTransitionPage<void>(child: child);
}

```