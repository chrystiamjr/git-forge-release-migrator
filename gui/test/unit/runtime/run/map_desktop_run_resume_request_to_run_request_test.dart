// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_desktop_run_resume_request_to_run_request.dart';

void main() {
  group('mapDesktopRunResumeRequestToRunRequest', () {
    test('maps release skip flags to runtime options', () {
      final request = mapDesktopRunResumeRequestToRunRequest(
        const DesktopRunResumeRequest(
          sourceProvider: 'github',
          sourceUrl: 'https://github.com/acme/source',
          sourceToken: 'source-token',
          targetProvider: 'gitlab',
          targetUrl: 'https://gitlab.com/acme/target',
          targetToken: 'target-token',
          skipTagMigration: true,
          skipReleaseMigration: true,
          skipReleaseAssetMigration: true,
        ),
      );

      expect(request.options.skipTagMigration, isTrue);
      expect(request.options.skipReleaseMigration, isTrue);
      expect(request.options.skipReleaseAssetMigration, isTrue);
    });
  });
}
