import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gfrm_gui/src/app/placeholders/gfrm_route_placeholder.dart';
import 'package:gfrm_gui/src/app/shell/gfrm_shell_page.dart';
import 'package:gfrm_gui/src/features/dashboard/presentation/dashboard_empty_page.dart';
import 'package:gfrm_gui/src/features/history/presentation/history_empty_page.dart';
import 'package:gfrm_gui/src/features/results/presentation/results_empty_page.dart';
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
              return _page(
                const GfrmRoutePlaceholder(
                  title: 'New Migration',
                  description: 'Wizard placeholder for source, target, filters, preflight, and confirmation.',
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoute.progress.path,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return _page(
                const GfrmRoutePlaceholder(
                  title: 'Run Progress',
                  description: 'Live migration phase, item table, action bar, and logs will mount here.',
                ),
              );
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
