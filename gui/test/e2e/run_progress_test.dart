import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/app/navigation/app_router.dart';
import 'package:gfrm_gui/src/application/run/contracts/desktop_run_controller.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_action_result.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_count_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_failure_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_progress_item.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_stat_card.dart';
import 'package:gfrm_gui/src/runtime/run/providers/desktop_run_controller_provider.dart';

void main() {
  testWidgets('renders idle current state before any stream event', (WidgetTester tester) async {
    final _RunController controller = _RunController();
    await _openProgress(tester, controller);
    expect(find.text('Status: idle'), findsOneWidget);
    expect(find.text('Phase: idle'), findsOneWidget);
    expect(find.text('No active run'), findsOneWidget);
    expect(_count(tester, 'tags', 'created'), '0');
  });

  testWidgets('renders phase, exact counters and items from ordered snapshots', (WidgetTester tester) async {
    final _RunController controller = _RunController();
    await _openProgress(tester, controller);
    controller.emit(
      const DesktopRunSnapshot.initial(sessionId: 'run-1').copyWith(
        lifecycle: 'running',
        activePhase: 'tags',
        tagCounts: const DesktopRunCountSummary(created: 2, wouldCreate: 3, skippedExisting: 4, failed: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Status: running'), findsOneWidget);
    expect(find.text('Phase: tags'), findsOneWidget);
    expect(_count(tester, 'tags', 'created'), '2');
    expect(_count(tester, 'tags', 'would create'), '3');
    expect(_count(tester, 'tags', 'skipped existing'), '4');
    expect(_count(tester, 'tags', 'failed'), '1');
    expect(find.text('Waiting for item updates.'), findsOneWidget);

    controller.emit(
      controller.currentSnapshot.copyWith(
        activePhase: 'releases',
        releaseCounts: const DesktopRunCountSummary(created: 5, wouldCreate: 2, skippedExisting: 3, failed: 4),
        progressItems: const <DesktopRunProgressItem>[
          DesktopRunProgressItem(kind: 'release', tag: 'v1.2.3', status: 'created', message: 'Release migrated'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phase: releases'), findsOneWidget);
    expect(_count(tester, 'tags', 'created'), '2');
    expect(_count(tester, 'releases', 'created'), '5');
    expect(_count(tester, 'releases', 'would create'), '2');
    expect(_count(tester, 'releases', 'skipped existing'), '3');
    expect(_count(tester, 'releases', 'failed'), '4');
    expect(find.text('v1.2.3'), findsOneWidget);
    expect(find.text('Release migrated'), findsOneWidget);
  });

  testWidgets('late navigation and re-entry show latest current snapshot without replay', (WidgetTester tester) async {
    final _RunController controller = _RunController();
    controller.currentSnapshot = const DesktopRunSnapshot.initial(
      sessionId: 'run-1',
    ).copyWith(lifecycle: 'running', activePhase: 'tags');
    final ProviderContainer container = await _openProgress(tester, controller);
    expect(find.text('Phase: tags'), findsOneWidget);
    container.read(appRouterProvider).go('/dashboard');
    await tester.pumpAndSettle();
    controller.emit(controller.currentSnapshot.copyWith(activePhase: 'releases'));
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/progress');
    await tester.pumpAndSettle();
    expect(find.text('Phase: releases'), findsOneWidget);
  });

  testWidgets('terminal state, failure, stream error and new run remain state driven', (WidgetTester tester) async {
    final _RunController controller = _RunController();
    await _openProgress(tester, controller);
    controller.emit(
      const DesktopRunSnapshot.initial(sessionId: 'run-1').copyWith(
        lifecycle: 'failed',
        activePhase: 'releases',
        completionStatus: 'partial_failure',
        latestFailure: const DesktopRunFailureSummary(
          code: 'upload_failed',
          message: 'Asset upload failed',
          retryable: true,
          phase: 'releases',
        ),
        releaseCounts: const DesktopRunCountSummary(created: 0, wouldCreate: 0, skippedExisting: 0, failed: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Status: failed'), findsOneWidget);
    expect(find.text('Outcome: partial_failure'), findsOneWidget);
    expect(find.text('Failure: Asset upload failed'), findsOneWidget);
    controller.updates.addError(StateError('do not display raw stream errors'));
    await tester.pumpAndSettle();
    expect(find.text('Live progress updates are unavailable.'), findsOneWidget);
    expect(_count(tester, 'releases', 'failed'), '1');
    controller.emit(
      const DesktopRunSnapshot.initial(sessionId: 'run-2').copyWith(lifecycle: 'running', activePhase: 'preflight'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phase: preflight'), findsOneWidget);
    expect(find.text('Failure: Asset upload failed'), findsNothing);
    expect(find.text('Live progress updates are unavailable.'), findsNothing);
    expect(_count(tester, 'releases', 'failed'), '0');
    controller.emit(controller.currentSnapshot.copyWith(lifecycle: 'completed', completionStatus: 'success'));
    await tester.pumpAndSettle();
    expect(find.text('Status: completed'), findsOneWidget);
    expect(find.text('Outcome: success'), findsOneWidget);
  });

  testWidgets('disposing app releases controller stream subscription', (WidgetTester tester) async {
    final _RunController controller = _RunController();
    await _openProgress(tester, controller);
    expect(controller.updates.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(controller.disposed, isTrue);
    expect(controller.updates.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });
}

String _count(WidgetTester tester, String kind, String outcome) {
  return tester.widget<GfrmStatCard>(find.byKey(ValueKey<String>('run-progress-$kind-$outcome'))).value;
}

Future<ProviderContainer> _openProgress(WidgetTester tester, _RunController controller) async {
  tester.view.physicalSize = const Size(1280, 1100);
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
  container.read(appRouterProvider).go('/progress');
  await tester.pumpAndSettle();
  return container;
}

final class _RunController implements DesktopRunController {
  final StreamController<DesktopRunSnapshot> updates = StreamController<DesktopRunSnapshot>.broadcast();
  bool disposed = false;
  @override
  DesktopRunSnapshot currentSnapshot = const DesktopRunSnapshot.initial();
  @override
  Stream<DesktopRunSnapshot> get snapshots => updates.stream;
  @override
  Stream<String> get logStream => throw StateError('Progress must not read terminal logs');
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
