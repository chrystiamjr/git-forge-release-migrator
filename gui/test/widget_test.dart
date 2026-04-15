import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/app/gfrm_shell_page.dart';

void main() {
  testWidgets('renders desktop scaffold shell', (WidgetTester tester) async {
    await tester.pumpWidget(const GfrmApp());

    expect(find.text('Desktop scaffold ready'), findsOneWidget);
    expect(find.text('Shared runtime contracts'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    final SizedBox sidebar = tester.widget<SizedBox>(find.byKey(GfrmShellPage.sidebarKey));

    expect(sidebar.width, 220);
  });
}
