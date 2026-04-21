// NOTE: Widget tests have been refactored and organized into separate files under gui/test/e2e/
//
// This file now serves as a smoke test entry point. Individual E2E tests are organized by feature:
// - shell_navigation_test.dart: Shell routing and sidebar indicators
// - dashboard_test.dart: Dashboard atoms and empty state
// - settings_navigation_test.dart: Settings sub-routes and active indicator persistence
// - wizard_step_1_test.dart: Repository validation flow
// - wizard_step_2_test.dart: Options, filters, and tag preview
// - wizard_step_3_preflight_test.dart: Preflight checklist, errors, warnings, and summary card
//
// To run all E2E tests:
//   flutter test gui/test/e2e/
//
// To run specific E2E test file:
//   flutter test gui/test/e2e/shell_navigation_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('E2E tests are organized in gui/test/e2e/ (smoke test placeholder)', (WidgetTester tester) async {
    expect(true, isTrue);
  });
}
