import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/app/app_routes.dart';

void main() {
  test('route map exposes all primary and settings destinations', () {
    expect(
      AppRoute.values.map((AppRoute route) => route.path),
      containsAll(<String>[
        '/dashboard',
        '/new-migration',
        '/progress',
        '/results',
        '/history',
        '/settings',
        '/settings/credentials',
        '/settings/profiles',
        '/settings/general',
      ]),
    );
  });

  test('active primary route ignores settings locations', () {
    expect(AppRoute.activePrimaryRouteFor('/dashboard'), AppRoute.dashboard);
    expect(AppRoute.activePrimaryRouteFor('/settings/credentials'), isNull);
    expect(AppRoute.isSettingsLocation('/settings/profiles'), isTrue);
  });
}
