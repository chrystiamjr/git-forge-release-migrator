@Tags(<String>['visual'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_gui/src/features/results/presentation/organisms/migration_results_summary.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

import '../support/results_fixture.dart';

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
    for (final String scenario in <String>[
      'idle',
      'success',
      'partial-failure',
      'partial-failure-details',
      'early-failure',
    ]) {
      testWidgets('$scenario Results content at ${size.width.toInt()}x${size.height.toInt()}', (
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
                    child: MigrationResultsSummary(snapshot: resultsSnapshot(scenario.replaceFirst('-details', ''))),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final String suffix = '${size.width.toInt()}x${size.height.toInt()}';
        if (scenario == 'partial-failure-details') {
          await tester.ensureVisible(find.text(resultsRetryCommand));
          await tester.pumpAndSettle();
          expect(find.text(resultsRetryCommand).hitTestable(), findsOneWidget);
        }
        // Missing baselines still fail. Save actual pixels separately so a reviewer
        // can propose canonical CI output without auto-updating golden baselines.
        await _compareWindow(tester, 'results-$scenario-$suffix');
      });
    }
  }
}

Future<void> _compareWindow(WidgetTester tester, String name) async {
  final Finder window = find.byKey(const ValueKey<String>('golden-window'));
  final File baseline = File('test/goldens/$name.png');
  if (!baseline.existsSync()) {
    final RenderRepaintBoundary boundary = tester.renderObject<RenderRepaintBoundary>(window);
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage();
      try {
        final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final File actual = File('test/visual/failures/${name}_actual.png');
        await actual.parent.create(recursive: true);
        await actual.writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
  await expectLater(window, matchesGoldenFile('../goldens/$name.png'));
}
