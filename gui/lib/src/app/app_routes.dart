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
