import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/app/shell/gfrm_shell_page.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

void main() {
  group('Settings Navigation E2E', () {
    group('Settings sub-route navigation', () {
      testWidgets('Settings → Credentials → Profiles → General → Settings (cycle)', (WidgetTester tester) async {
        _setDesktopSurface(tester);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
        expect(
          find.text('Profile-scoped provider tokens and credential health checks will mount here.'),
          findsOneWidget,
        );

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
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
        await tester.pumpAndSettle();

        final Color activeColor = GfrmAppTheme.colors.accent;

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
  });
}

void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
}
