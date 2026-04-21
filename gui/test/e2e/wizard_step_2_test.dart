import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';

void main() {
  group('Wizard Step 2: Options and Filters E2E', () {
    testWidgets('navigates to Step 2 and displays options and tag preview', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();

      // Fill Step 1
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-source-url')),
        'https://github.com/acme/source',
      );
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-source-token')), 'source-token');
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-target-url')),
        'https://gitlab.com/acme/target',
      );
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-target-token')), 'target-token');
      await tester.pump();
      await tester.tap(find.text('VALIDATE CONNECTIONS'));
      await tester.pumpAndSettle();

      // Move to Step 2
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Options and filters'), findsOneWidget);
      expect(find.text('Migrate releases'), findsOneWidget);
      expect(find.text('Migrate release assets'), findsOneWidget);
      expect(find.text('Matching tag preview'), findsOneWidget);
    });

    testWidgets('toggles migrate releases and release assets options', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();

      // Fill Step 1
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-source-url')),
        'https://github.com/acme/source',
      );
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-source-token')), 'source-token');
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-target-url')),
        'https://gitlab.com/acme/target',
      );
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-target-token')), 'target-token');
      await tester.pump();
      await tester.tap(find.text('VALIDATE CONNECTIONS'));
      await tester.pumpAndSettle();

      // Move to Step 2
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();

      // Toggle options
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
    });

    testWidgets('filters tags by range in matching tag preview', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();

      // Fill Step 1
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-source-url')),
        'https://github.com/acme/source',
      );
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-source-token')), 'source-token');
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-migration-target-url')),
        'https://gitlab.com/acme/target',
      );
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-target-token')), 'target-token');
      await tester.pump();
      await tester.tap(find.text('VALIDATE CONNECTIONS'));
      await tester.pumpAndSettle();

      // Move to Step 2
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();

      // Set tag range
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-from-tag')), 'v2.0.1');
      await tester.enterText(find.byKey(const ValueKey<String>('new-migration-to-tag')), 'v2.1.0');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'v2.1.0'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'v2.0.1'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'v2.0.0'), findsNothing);
    });
  });
}

void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
}
