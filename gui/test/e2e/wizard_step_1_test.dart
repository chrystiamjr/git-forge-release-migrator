import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';

void main() {
  group('Wizard Step 1: Repository Validation E2E', () {
    testWidgets('navigates to Step 1 from dashboard', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Source repository'), findsOneWidget);
      expect(find.text('Target repository'), findsOneWidget);
    });

    testWidgets('validates repositories before moving to options step', (WidgetTester tester) async {
      _setDesktopSurface(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: GfrmApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEW MIGRATION'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 3'), findsOneWidget);

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

      expect(find.text('Connection validated'), findsNWidgets(2));

      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Options and filters'), findsOneWidget);
    });
  });
}

void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
}
