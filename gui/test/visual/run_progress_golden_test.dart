@Tags(<String>['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_count_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_failure_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_progress_item.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/features/progress/presentation/organisms/run_progress_summary.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

void main() {
  setUpAll(() async {
    for (final MapEntry<String, String> font in <String, String>{
      'IBMPlexSans': 'assets/fonts/IBMPlexSans-Variable.ttf',
      'IBMPlexMono': 'assets/fonts/IBMPlexMono-Regular.ttf',
      'Inter': 'assets/fonts/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final FontLoader loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });

  for (final Size size in <Size>[const Size(1280, 800), const Size(1024, 768)]) {
    for (final String scenario in <String>['idle', 'running', 'failure']) {
      testWidgets('$scenario progress content at ${size.width.toInt()}x${size.height.toInt()}', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey<String>('golden-window'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: GfrmAppTheme.themeData.copyWith(platform: TargetPlatform.linux),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: RunProgressSummary(snapshot: _snapshot(scenario)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final String suffix = '${size.width.toInt()}x${size.height.toInt()}';
        await expectLater(
          find.byKey(const ValueKey<String>('golden-window')),
          matchesGoldenFile('../goldens/progress-$scenario-$suffix.png'),
        );
        if (scenario != 'idle') {
          await tester.ensureVisible(find.text('Release already exists'));
          await tester.pumpAndSettle();
          expect(find.text('Release already exists').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}

DesktopRunSnapshot _snapshot(String scenario) {
  if (scenario == 'idle') {
    return const DesktopRunSnapshot.initial();
  }
  return const DesktopRunSnapshot.initial(sessionId: 'golden-run').copyWith(
    lifecycle: scenario == 'failure' ? 'failed' : 'running',
    activePhase: 'releases',
    completionStatus: scenario == 'failure' ? 'partial_failure' : '',
    latestFailure: scenario == 'failure'
        ? const DesktopRunFailureSummary(
            code: 'upload',
            message: 'Asset upload failed.',
            retryable: true,
            phase: 'releases',
          )
        : null,
    tagCounts: const DesktopRunCountSummary(created: 12, wouldCreate: 0, skippedExisting: 3, failed: 0),
    releaseCounts: DesktopRunCountSummary(
      created: 4,
      wouldCreate: 0,
      skippedExisting: 1,
      failed: scenario == 'failure' ? 1 : 0,
    ),
    progressItems: const <DesktopRunProgressItem>[
      DesktopRunProgressItem(kind: 'tag', tag: 'v1.2.3', status: 'created', message: 'Tag migrated'),
      DesktopRunProgressItem(kind: 'release', tag: 'v1.2.3', status: 'created', message: 'Release and assets migrated'),
      DesktopRunProgressItem(
        kind: 'release',
        tag: 'v1.2.2',
        status: 'skipped_existing',
        message: 'Release already exists',
      ),
    ],
  );
}
