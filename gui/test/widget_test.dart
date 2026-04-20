import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/app/shell/gfrm_shell_page.dart';

void main() {
  testWidgets('renders dashboard as startup route inside desktop shell', (WidgetTester tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
    await tester.pumpAndSettle();

    expect(find.text('No migrations yet'), findsOneWidget);
    expect(find.text('Start your first release migration between Git forges'), findsOneWidget);
    expect(find.text('SUCCESS RATE'), findsOneWidget);
    expect(find.text('TOTAL MIGRATIONS'), findsOneWidget);
    expect(find.text('FAILURES'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);

    final SizedBox sidebar = tester.widget<SizedBox>(find.byKey(GfrmShellPage.sidebarKey));

    expect(sidebar.width, 220);
  });

  testWidgets('dashboard empty state navigates to new migration', (WidgetTester tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NEW MIGRATION'));
    await tester.pumpAndSettle();

    expect(find.text('New Migration'), findsWidgets);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('Source repository'), findsOneWidget);
    expect(find.text('Target repository'), findsOneWidget);
  });

  testWidgets('navigates primary routes and highlights the active item', (WidgetTester tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsWidgets);
    expect(find.text('No migration history'), findsOneWidget);
    expect(find.text('Completed and resumed migrations will appear here once you run them.'), findsOneWidget);

    final Finder historyIcon = find.byIcon(Icons.history);
    final Icon icon = tester.widget<Icon>(historyIcon.first);

    expect(icon.color, const Color(0xFF818CF8));
  });

  testWidgets('settings route highlights gear instead of primary nav items', (WidgetTester tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings landing page for credentials, profiles, and general preferences.'), findsOneWidget);

    final Icon settingsIcon = tester.widget<Icon>(find.byIcon(Icons.settings_outlined).first);
    final Icon dashboardIcon = tester.widget<Icon>(find.byIcon(Icons.dashboard_outlined).first);

    expect(settingsIcon.color, const Color(0xFF818CF8));
    expect(dashboardIcon.color, const Color(0xFF94A3B8));
  });

  testWidgets('resolves every declared shell route', (WidgetTester tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
    await tester.pumpAndSettle();

    final Map<String, String> expectedTitles = <String, String>{
      '/dashboard': 'No migrations yet',
      '/new-migration': 'New Migration',
      '/progress': 'Run Progress',
      '/results': 'No results to display',
      '/history': 'No migration history',
      '/settings': 'Settings',
      '/settings/credentials': 'Credential Management',
      '/settings/profiles': 'Profiles',
      '/settings/general': 'General',
    };

    for (final MapEntry<String, String> route in expectedTitles.entries) {
      tester.element(find.byKey(GfrmShellPage.contentKey)).go(route.key);
      await tester.pumpAndSettle();

      expect(find.text(route.value), findsWidgets, reason: 'Expected ${route.key} to render ${route.value}.');
    }
  });

  testWidgets('results remains accessible while idle and shows empty state', (WidgetTester tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Results'));
    await tester.pumpAndSettle();

    expect(find.text('No results to display'), findsOneWidget);
    expect(
      find.text('Migration summaries and artifact shortcuts will appear here after a run finishes.'),
      findsOneWidget,
    );
  });

  group('Primary route transitions (smoke tests)', () {
    testWidgets('navigates Dashboard → New Migration → Progress → Results → History → Dashboard (cycle)', (
      WidgetTester tester,
    ) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      // Verify startup at Dashboard
      expect(find.text('No migrations yet'), findsOneWidget);

      // Dashboard → New Migration
      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 2'), findsOneWidget);

      // New Migration → Progress
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/progress');
      await tester.pumpAndSettle();
      expect(find.text('Live migration phase, item table, action bar, and logs will mount here.'), findsOneWidget);

      // Progress → Results
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/results');
      await tester.pumpAndSettle();
      expect(find.text('No results to display'), findsOneWidget);

      // Results → History
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/history');
      await tester.pumpAndSettle();
      expect(find.text('No migration history'), findsOneWidget);

      // History → Dashboard
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/dashboard');
      await tester.pumpAndSettle();
      expect(find.text('No migrations yet'), findsOneWidget);
    });

    testWidgets('sidebar active indicator updates for Dashboard, New Migration, Progress, Results, History', (
      WidgetTester tester,
    ) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      final Color activeColor = const Color(0xFF818CF8);
      final Color inactiveColor = const Color(0xFF94A3B8);

      // Dashboard (active)
      var dashboardIcon = tester.widget<Icon>(find.byIcon(Icons.dashboard_outlined).first);
      expect(dashboardIcon.color, activeColor);

      // Navigate to New Migration
      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();
      dashboardIcon = tester.widget<Icon>(find.byIcon(Icons.dashboard_outlined).first);
      expect(dashboardIcon.color, inactiveColor);

      // Navigate to Progress
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/progress');
      await tester.pumpAndSettle();
      var progressIcon = tester.widget<Icon>(find.byIcon(Icons.sync_outlined).first);
      expect(progressIcon.color, activeColor);

      // Navigate to Results
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/results');
      await tester.pumpAndSettle();
      progressIcon = tester.widget<Icon>(find.byIcon(Icons.sync_outlined).first);
      expect(progressIcon.color, inactiveColor);
      var resultsIcon = tester.widget<Icon>(find.byIcon(Icons.task_alt_outlined).first);
      expect(resultsIcon.color, activeColor);

      // Navigate to History
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/history');
      await tester.pumpAndSettle();
      resultsIcon = tester.widget<Icon>(find.byIcon(Icons.task_alt_outlined).first);
      expect(resultsIcon.color, inactiveColor);
      var historyIcon = tester.widget<Icon>(find.byIcon(Icons.history).first);
      expect(historyIcon.color, activeColor);
    });
  });

  group('Settings sub-route navigation', () {
    testWidgets('Settings → Credentials → Profiles → General → Settings (cycle)', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      // Navigate to Settings (main)
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings landing page for credentials, profiles, and general preferences.'), findsOneWidget);

      // Settings → Credentials
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/settings/credentials');
      await tester.pumpAndSettle();
      expect(find.text('Credential Management'), findsWidgets);
      expect(find.text('Profile-scoped provider tokens and credential health checks will mount here.'), findsOneWidget);

      // Credentials → Profiles
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/settings/profiles');
      await tester.pumpAndSettle();
      expect(find.text('Profiles'), findsWidgets);
      expect(find.text('Profile creation, editing, defaults, and provider mapping will mount here.'), findsOneWidget);

      // Profiles → General
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/settings/general');
      await tester.pumpAndSettle();
      expect(find.text('General'), findsWidgets);
      expect(find.text('App preferences, diagnostics defaults, and layout options will mount here.'), findsOneWidget);

      // General → Settings (root)
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/settings');
      await tester.pumpAndSettle();
      expect(find.text('Settings landing page for credentials, profiles, and general preferences.'), findsOneWidget);
    });

    testWidgets('Settings icon remains active while navigating sub-routes', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      final Color activeColor = const Color(0xFF818CF8);

      // Navigate to Settings
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Verify settings icon is active
      var settingsIcon = tester.widget<Icon>(find.byIcon(Icons.settings_outlined).first);
      expect(settingsIcon.color, activeColor);

      // Navigate to Credentials (sub-route)
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/settings/credentials');
      await tester.pumpAndSettle();
      settingsIcon = tester.widget<Icon>(find.byIcon(Icons.settings_outlined).first);
      expect(settingsIcon.color, activeColor);

      // Navigate to Profiles (sub-route)
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/settings/profiles');
      await tester.pumpAndSettle();
      settingsIcon = tester.widget<Icon>(find.byIcon(Icons.settings_outlined).first);
      expect(settingsIcon.color, activeColor);

      // Navigate to General (sub-route)
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/settings/general');
      await tester.pumpAndSettle();
      settingsIcon = tester.widget<Icon>(find.byIcon(Icons.settings_outlined).first);
      expect(settingsIcon.color, activeColor);
    });
  });

  group('Dashboard widget atoms rendering in context', () {
    testWidgets('Dashboard renders GfrmStatCard atoms with correct labels and values', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      // Verify Dashboard page renders with correct stat card labels and values
      expect(find.text('SUCCESS RATE'), findsOneWidget);
      expect(find.text('TOTAL MIGRATIONS'), findsOneWidget);
      expect(find.text('FAILURES'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
    });

    testWidgets('Dashboard empty state GfrmButton responds to tap', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      // Verify button text exists
      expect(find.text('NEW MIGRATION'), findsOneWidget);

      // Tap button and verify navigation
      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();

      expect(find.text('New Migration'), findsWidgets);
    });
  });

  group('Window size validation (1280x800)', () {
    testWidgets('desktop surface renders correctly at 1280x800 resolution', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      // Verify sidebar width
      final SizedBox sidebar = tester.widget<SizedBox>(find.byKey(GfrmShellPage.sidebarKey));
      expect(sidebar.width, 220);

      // Verify surface dimensions
      expect(tester.view.physicalSize, const Size(1280, 800));
    });
  });

  group('Wizard step transitions', () {
    testWidgets('validates repositories before moving to options step', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 2'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-source-url')),
        'https://github.com/acme/source',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-target-url')),
        'https://gitlab.com/acme/target',
      );
      await tester.pump();
      await tester.tap(find.text('VALIDATE CONNECTIONS'));
      await tester.pumpAndSettle();

      expect(find.text('Connection validated'), findsNWidgets(2));

      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.text('Options and filters'), findsOneWidget);
      expect(find.text('Migrate releases'), findsOneWidget);
      expect(find.text('Migrate release assets'), findsOneWidget);
      expect(find.text('Matching tag preview'), findsOneWidget);

      await tester.tap(find.text('Migrate releases'));
      await tester.tap(find.text('Migrate release assets'));
      await tester.pumpAndSettle();

      final SwitchListTile releaseToggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Migrate releases'),
      );
      final SwitchListTile assetToggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Migrate release assets'),
      );
      expect(releaseToggle.value, isFalse);
      expect(assetToggle.value, isFalse);

      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-include-pattern')), 'v2*');
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-exclude-pattern')), 'v2.0.0');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'v2.1.0'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'v2.0.1'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'v2.0.0'), findsNothing);
    });

    testWidgets('progress-to-results transition on migration completion', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      // Navigate to Progress
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/progress');
      await tester.pumpAndSettle();
      expect(find.text('Live migration phase, item table, action bar, and logs will mount here.'), findsOneWidget);

      // Simulate completion by navigating to Results
      tester.element(find.byKey(GfrmShellPage.contentKey)).go('/results');
      await tester.pumpAndSettle();
      expect(find.text('No results to display'), findsOneWidget);
    });
  });
}

void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
