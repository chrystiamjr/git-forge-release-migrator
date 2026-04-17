import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/app/gfrm_shell_page.dart';

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
    expect(find.text('Wizard placeholder for source, target, filters, preflight, and confirmation.'), findsOneWidget);
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
}

void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
