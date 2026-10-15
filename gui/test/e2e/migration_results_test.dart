// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_artifact_paths.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_failure.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_lifecycle.dart';
import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/app/navigation/app_router.dart';
import 'package:gfrm_gui/src/application/run/contracts/desktop_run_controller.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_action_result.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_stat_card.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_run_state_to_snapshot.dart';
import 'package:gfrm_gui/src/runtime/run/providers/desktop_run_controller_provider.dart';

import '../support/results_fixture.dart';

void main() {
  testWidgets('idle and active runs hide final outputs even when intermediate paths exist', (
    WidgetTester tester,
  ) async {
    final _ResultsController controller = _ResultsController();
    await _openResults(tester, controller);
    expect(find.text('No results to display'), findsOneWidget);
    controller.emit(resultsSnapshot('partial-failure').copyWith(lifecycle: 'running'));
    await tester.pumpAndSettle();
    expect(find.text('Migration in progress'), findsOneWidget);
    expect(find.text('Artifacts'), findsNothing);
    expect(find.text(resultsRetryCommand), findsNothing);
    expect(find.text('Outcome: partial_failure'), findsNothing);
  });

  testWidgets('late entry renders successful final RunState counters and reported artifacts', (
    WidgetTester tester,
  ) async {
    final _ResultsController controller = _ResultsController()..currentSnapshot = resultsSnapshot('success');
    await _openResults(tester, controller);
    expect(find.text('Status: completed'), findsOneWidget);
    expect(find.text('Outcome: success'), findsOneWidget);
    expect(find.text('Total tags: 3'), findsOneWidget);
    expect(find.text('Failed tags: 0'), findsOneWidget);
    for (final String kind in <String>['tags', 'releases']) {
      for (final String outcome in <String>['created', 'would create', 'skipped existing']) {
        expect(_count(tester, kind, outcome), '1');
      }
      expect(_count(tester, kind, 'failed'), '0');
    }
    for (final String name in <String>['summary.json', 'failed-tags.txt', 'migration-log.jsonl']) {
      expect(find.text('$resultsDirectory/$name'), findsOneWidget);
    }
    expect(find.text('Retry from the terminal'), findsNothing);
  });

  testWidgets('completed partial failure exposes the exact runtime retry command', (WidgetTester tester) async {
    final _ResultsController controller = _ResultsController();
    await _openResults(tester, controller);
    controller.emit(resultsSnapshot('partial-failure'));
    await tester.pumpAndSettle();
    expect(find.text('Status: completed'), findsOneWidget);
    expect(find.text('Outcome: partial_failure'), findsOneWidget);
    expect(find.text('Failed tags: 1'), findsOneWidget);
    expect(_count(tester, 'releases', 'failed'), '1');
    expect(find.text('Failed items'), findsOneWidget);
    expect(find.text('release: v3.0.0'), findsOneWidget);
    expect(find.text('Asset upload failed.'), findsOneWidget);
    expect(find.text(resultsRetryCommand), findsOneWidget);
    expect(find.text('Outcome: success'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('early failure exposes context without inventing artifacts or retry', (WidgetTester tester) async {
    final _ResultsController controller = _ResultsController()..currentSnapshot = resultsSnapshot('early-failure');
    expect(controller.currentSnapshot.canResume, isTrue);
    await _openResults(tester, controller);
    expect(find.text('Status: failed'), findsOneWidget);
    expect(find.text('Code: preflight_failed'), findsOneWidget);
    expect(find.text('Failure phase: preflight'), findsOneWidget);
    expect(find.text('Destination tags are missing.'), findsOneWidget);
    expect(find.text('No artifact paths were reported for this run.'), findsOneWidget);
    expect(find.text('summary.json'), findsNothing);
    expect(find.text('Retry from the terminal'), findsNothing);
    expect(find.byKey(const ValueKey<String>('run-results-outcome')), findsNothing);
  });

  testWidgets('partial artifact set and blank retry are rendered without fallback guesses', (
    WidgetTester tester,
  ) async {
    final _ResultsController controller = _ResultsController()
      ..currentSnapshot = mapRunStateToSnapshot(
        sessionId: 'session-1',
        state: resultsState('partial-failure').copyWith(
          retryCommand: '  ',
          artifactPaths: const RunStateArtifactPaths(
            pathsByType: <String, String>{'migration_log': 'custom/log.jsonl', 'summary': '  '},
          ),
        ),
      );
    await _openResults(tester, controller);
    expect(find.text('custom/log.jsonl'), findsOneWidget);
    expect(find.text('summary.json'), findsNothing);
    expect(find.text('failed-tags.txt'), findsNothing);
    expect(find.text('Retry from the terminal'), findsNothing);
  });

  testWidgets('re-entry, stream errors and a new run preserve only current results', (WidgetTester tester) async {
    final _ResultsController controller = _ResultsController()..currentSnapshot = resultsSnapshot('early-failure');
    final ProviderContainer container = await _openResults(tester, controller);
    container.read(appRouterProvider).go('/dashboard');
    await tester.pumpAndSettle();
    controller.emit(resultsSnapshot('partial-failure'));
    container.read(appRouterProvider).go('/results');
    await tester.pumpAndSettle();
    expect(find.text(resultsRetryCommand), findsOneWidget);
    expect(find.text('Destination tags are missing.'), findsNothing);
    controller.updates.addError(StateError('private transport failure'));
    await tester.pumpAndSettle();
    expect(find.text('Result updates are unavailable.'), findsOneWidget);
    expect(find.text(resultsRetryCommand), findsOneWidget);
    expect(find.textContaining('private transport failure'), findsNothing);
    controller.emit(resultsSnapshot('running').copyWith(sessionId: 'session-2'));
    await tester.pumpAndSettle();
    expect(find.text('Migration in progress'), findsOneWidget);
    expect(find.text(resultsRetryCommand), findsNothing);
    expect(find.text('Result updates are unavailable.'), findsNothing);
    expect(find.text('Artifacts'), findsNothing);
    controller.emit(resultsSnapshot('success').copyWith(sessionId: 'session-2'));
    await tester.pumpAndSettle();
    expect(find.text('Outcome: success'), findsOneWidget);
  });

  testWidgets('disposing Results releases the controller subscription', (WidgetTester tester) async {
    final _ResultsController controller = _ResultsController();
    await _openResults(tester, controller);
    expect(controller.updates.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(controller.disposed, isTrue);
    expect(controller.updates.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final Size size in <Size>[const Size(1280, 800), const Size(1024, 768)]) {
    testWidgets('long failure, paths and retry remain reachable at $size', (WidgetTester tester) async {
      final String longPath = 'migration-results/${List<String>.filled(20, 'long-folder-name').join('/')}/summary.json';
      final String longCommand = 'gfrm resume --session-file "$longPath"';
      final _ResultsController controller = _ResultsController()
        ..currentSnapshot = mapRunStateToSnapshot(
          sessionId: 'session-1',
          state: resultsState('partial-failure').copyWith(
            lifecycle: RunStateLifecycle.failed,
            latestFailure: RunStateFailure(
              code: 'asset_upload',
              message: List<String>.filled(20, 'Destination rejected the asset.').join(' '),
              retryable: true,
              phase: 'releases',
            ),
            artifactPaths: RunStateArtifactPaths(pathsByType: <String, String>{'summary': longPath}),
            retryCommand: longCommand,
          ),
        );
      await _openResults(tester, controller, size: size);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(longPath));
      await tester.pumpAndSettle();
      expect(find.text(longPath).hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text(longCommand));
      await tester.pumpAndSettle();
      expect(find.text(longCommand).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

String _count(WidgetTester tester, String kind, String outcome) =>
    tester.widget<GfrmStatCard>(find.byKey(ValueKey<String>('run-results-$kind-$outcome'))).value;

Future<ProviderContainer> _openResults(
  WidgetTester tester,
  _ResultsController controller, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        desktopRunControllerFactoryProvider.overrideWith(
          (ref) =>
              () => controller,
        ),
      ],
      child: const GfrmApp(),
    ),
  );
  await tester.pumpAndSettle();
  final ProviderContainer container = ProviderScope.containerOf(tester.element(find.byType(GfrmApp)));
  container.read(appRouterProvider).go('/results');
  await tester.pumpAndSettle();
  return container;
}

final class _ResultsController implements DesktopRunController {
  final StreamController<DesktopRunSnapshot> updates = StreamController<DesktopRunSnapshot>.broadcast();
  bool disposed = false;
  @override
  DesktopRunSnapshot currentSnapshot = const DesktopRunSnapshot.initial();
  @override
  Stream<DesktopRunSnapshot> get snapshots => updates.stream;
  @override
  Stream<String> get logStream => throw StateError('Results must not parse logs');
  void emit(DesktopRunSnapshot snapshot) {
    currentSnapshot = snapshot;
    updates.add(snapshot);
  }

  @override
  Future<DesktopPreflightSummary> evaluatePreflight(DesktopPreflightRequest request) => throw UnimplementedError();
  @override
  Future<DesktopRunSession> startRun(DesktopRunStartRequest request) => throw UnimplementedError();
  @override
  Future<DesktopRunSession> resumeRun(DesktopRunResumeRequest request) => throw UnimplementedError();
  @override
  Future<DesktopRunActionResult> cancelActiveRun() => throw UnimplementedError();
  @override
  void dispose() {
    disposed = true;
    unawaited(updates.close());
  }
}
