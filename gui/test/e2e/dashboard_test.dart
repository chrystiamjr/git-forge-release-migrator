import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';

void main() {
  group('Dashboard E2E', () {
    testWidgets('empty state navigates to new migration', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();

      expect(find.text('New Migration'), findsWidgets);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Source repository'), findsOneWidget);
      expect(find.text('Target repository'), findsOneWidget);
    });

    group('Dashboard widget atoms rendering in context', () {
      testWidgets('renders GfrmStatCard atoms with correct labels and values', (WidgetTester tester) async {
        _setDesktopSurface(tester);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
        await tester.pumpAndSettle();

        // Verify Dashboard page renders with correct stat card labels and values
        expect(find.text('SUCCESS RATE'), findsOneWidget);
        expect(find.text('TOTAL MIGRATIONS'), findsOneWidget);
        expect(find.text('FAILURES'), findsOneWidget);
        expect(find.text('0%'), findsOneWidget);
        expect(find.text('0'), findsNWidgets(2));
      });

      testWidgets('empty state GfrmButton responds to tap', (WidgetTester tester) async {
        _setDesktopSurface(tester);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
  });
}

void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
}
