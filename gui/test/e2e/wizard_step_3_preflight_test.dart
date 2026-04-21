import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_preflight_check_item.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_controller.dart';
import 'package:gfrm_gui/src/features/new_migration/application/new_migration_wizard_state.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/organisms/new_migration_preflight_step.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

void main() {
  group('Wizard Step 3: Preflight Review E2E', () {
    testWidgets('navigates to Step 3 from Step 2', (WidgetTester tester) async {
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

      // Move to Step 3
      await tester.tap(find.text('REVIEW REQUEST'));
      await tester.pumpAndSettle();

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Preflight Results'), findsOneWidget);
      expect(find.text('Migration Summary'), findsOneWidget);
      expect(find.text('START MIGRATION'), findsOneWidget);
    });

    testWidgets('renders all preflight check types (OK, Warning, Error)', (WidgetTester tester) async {
      final NewMigrationWizardState state = NewMigrationWizardState(
        sourceUrl: 'https://github.com/acme/source',
        targetUrl: 'https://gitlab.com/acme/target',
        preflightSummary: DesktopPreflightSummary(
          status: 'failed',
          checks: const <DesktopPreflightCheckItem>[
            DesktopPreflightCheckItem(code: 'ok', message: 'Provider pair is supported.', status: 'ok'),
            DesktopPreflightCheckItem(
              code: 'warning',
              message: 'Settings profile release was not found.',
              status: 'warning',
              hint: 'Profile-backed settings will not apply.',
            ),
            DesktopPreflightCheckItem(
              code: 'error',
              message: 'Missing target token.',
              status: 'error',
              hint: 'Provide a target token.',
            ),
          ],
          checkCount: 3,
          blockingCount: 1,
          warningCount: 1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: GfrmAppTheme.themeData,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewMigrationPreflightStep(state: state, controller: NewMigrationWizardController(null)),
            ),
          ),
        ),
      );

      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
    });

    testWidgets('displays blocking error banner when blocking errors exist', (WidgetTester tester) async {
      final NewMigrationWizardState state = NewMigrationWizardState(
        sourceUrl: 'https://github.com/acme/source',
        targetUrl: 'https://gitlab.com/acme/target',
        preflightSummary: DesktopPreflightSummary(
          status: 'failed',
          checks: const <DesktopPreflightCheckItem>[
            DesktopPreflightCheckItem(code: 'ok', message: 'Provider pair is supported.', status: 'ok'),
            DesktopPreflightCheckItem(
              code: 'error',
              message: 'Missing target token.',
              status: 'error',
              hint: 'Provide a target token.',
            ),
          ],
          checkCount: 2,
          blockingCount: 1,
          warningCount: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: GfrmAppTheme.themeData,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewMigrationPreflightStep(state: state, controller: NewMigrationWizardController(null)),
            ),
          ),
        ),
      );

      expect(find.text('1 blocking errors must be resolved before migration can start.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('new-migration-preflight-blocking-banner')), findsOneWidget);
    });

    testWidgets('disables Start Migration button when blocking errors exist', (WidgetTester tester) async {
      final NewMigrationWizardState state = NewMigrationWizardState(
        sourceUrl: 'https://github.com/acme/source',
        targetUrl: 'https://gitlab.com/acme/target',
        preflightSummary: DesktopPreflightSummary(
          status: 'failed',
          checks: const <DesktopPreflightCheckItem>[
            DesktopPreflightCheckItem(code: 'ok', message: 'Provider pair is supported.', status: 'ok'),
            DesktopPreflightCheckItem(
              code: 'error',
              message: 'Missing target token.',
              status: 'error',
              hint: 'Provide a target token.',
            ),
          ],
          checkCount: 2,
          blockingCount: 1,
          warningCount: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: GfrmAppTheme.themeData,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewMigrationPreflightStep(state: state, controller: NewMigrationWizardController(null)),
            ),
          ),
        ),
      );

      expect(
        tester.widget<InkWell>(find.ancestor(of: find.text('START MIGRATION'), matching: find.byType(InkWell))).onTap,
        isNull,
      );
    });

    testWidgets('keeps Start Migration enabled when only warnings exist', (WidgetTester tester) async {
      final NewMigrationWizardState state = NewMigrationWizardState(
        sourceUrl: 'https://github.com/acme/source',
        targetUrl: 'https://gitlab.com/acme/target',
        preflightSummary: DesktopPreflightSummary(
          status: 'warning',
          checks: const <DesktopPreflightCheckItem>[
            DesktopPreflightCheckItem(
              code: 'warning',
              message: 'Settings profile release was not found.',
              status: 'warning',
              hint: 'Profile-backed settings will not apply.',
            ),
          ],
          checkCount: 1,
          blockingCount: 0,
          warningCount: 1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: GfrmAppTheme.themeData,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewMigrationPreflightStep(state: state, controller: NewMigrationWizardController(null)),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey<String>('new-migration-preflight-blocking-banner')), findsNothing);
      expect(
        tester.widget<InkWell>(find.ancestor(of: find.text('START MIGRATION'), matching: find.byType(InkWell))).onTap,
        isNotNull,
      );
    });

    testWidgets('renders all checks OK when preflight passes', (WidgetTester tester) async {
      final NewMigrationWizardState state = NewMigrationWizardState(
        sourceUrl: 'https://github.com/acme/source',
        targetUrl: 'https://gitlab.com/acme/target',
        preflightSummary: DesktopPreflightSummary(
          status: 'ok',
          checks: const <DesktopPreflightCheckItem>[
            DesktopPreflightCheckItem(code: 'ok_1', message: 'Provider pair is supported.', status: 'ok'),
            DesktopPreflightCheckItem(code: 'ok_2', message: 'Source token is valid.', status: 'ok'),
            DesktopPreflightCheckItem(code: 'ok_3', message: 'Target token is valid.', status: 'ok'),
          ],
          checkCount: 3,
          blockingCount: 0,
          warningCount: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: GfrmAppTheme.themeData,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewMigrationPreflightStep(state: state, controller: NewMigrationWizardController(null)),
            ),
          ),
        ),
      );

      expect(find.text('OK'), findsWidgets);
      expect(find.text('Provider pair is supported.'), findsOneWidget);
      expect(find.text('Source token is valid.'), findsOneWidget);
      expect(find.text('Target token is valid.'), findsOneWidget);
      expect(find.text('Blocked'), findsNothing);
    });
  });
}

void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
}
