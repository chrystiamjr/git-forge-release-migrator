// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_dart/src/application/preflight_service.dart';
import 'package:gfrm_dart/src/application/run_service.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/runtime/run/services/gfrm_desktop_run_controller.dart';

import '../../../support/run_service_fakes.dart';

void main() {
  group('GfrmDesktopRunController', () {
    late GfrmDesktopRunController controller;

    setUp(() {
      controller = GfrmDesktopRunController(
        logger: createSilentLogger(),
        runService: RunService(
          logger: createSilentLogger(),
          registryFactory: (_) =>
              buildTestRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
        ),
        preflightService: PreflightService(),
        registryFactory: (_) =>
            buildTestRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('maps preflight request into typed summary', () async {
      final summary = await controller.evaluatePreflight(
        const DesktopPreflightRequest(
          sourceProvider: 'github',
          sourceUrl: 'https://github.com/acme/source',
          sourceToken: 'source-token',
          targetProvider: 'gitlab',
          targetUrl: 'https://gitlab.com/acme/target',
          targetToken: 'target-token',
        ),
      );

      expect(summary.status, 'ok');
      expect(summary.checkCount, 7);
      expect(summary.blockingCount, 0);
      expect(summary.warningCount, 0);
      expect(summary.checks.any((item) => item.code == 'supported-command'), isTrue);
    });

    test('starts run and emits ordered snapshots', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('gfrm-gui-start-');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final List<DesktopRunSnapshot> snapshots = <DesktopRunSnapshot>[];
      final StreamSubscription<DesktopRunSnapshot> subscription = controller.snapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);

      final session = await controller.startRun(
        DesktopRunStartRequest(
          sourceProvider: 'github',
          sourceUrl: 'https://github.com/acme/source',
          sourceToken: 'source-token',
          targetProvider: 'gitlab',
          targetUrl: 'https://gitlab.com/acme/target',
          targetToken: 'target-token',
          workdir: tempDir.path,
        ),
      );

      expect(session.initialSnapshot.sessionId, isNotEmpty);
      expect(session.initialSnapshot.lifecycle, 'idle');

      final completion = await session.completion;
      await Future<void>.delayed(Duration.zero);

      expect(completion.status, 'success');
      expect(snapshots, isNotEmpty);
      expect(snapshots.first.lifecycle, 'running');
      expect(snapshots.last.completionStatus, 'success');
      expect(snapshots.last.tagCounts.created, 1);
      expect(snapshots.last.releaseCounts.created, 1);
      expect(controller.currentSnapshot.completionStatus, 'success');
      expect(controller.currentSnapshot.progressPercent, 1.0);
      expect(controller.currentSnapshot.elapsedTime, isNot(Duration.zero));
      expect(controller.currentSnapshot.estimatedRemainingTime, isNull);
    });

    test('logStream emits formatted lines during run', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('gfrm-gui-log-');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final List<String> logLines = <String>[];
      final StreamSubscription<String> logSub = controller.logStream.listen(logLines.add);
      addTearDown(logSub.cancel);

      final session = await controller.startRun(
        DesktopRunStartRequest(
          sourceProvider: 'github',
          sourceUrl: 'https://github.com/acme/source',
          sourceToken: 'source-token',
          targetProvider: 'gitlab',
          targetUrl: 'https://gitlab.com/acme/target',
          targetToken: 'target-token',
          workdir: tempDir.path,
        ),
      );
      await session.completion;
      await Future<void>.delayed(Duration.zero);

      expect(logLines, isNotEmpty);
      expect(logLines.any((line) => line.contains('Run started')), isTrue);
      expect(logLines.any((line) => line.contains('run_completed') || line.contains('Run completed')), isTrue);
    });

    test('snapshot progressPercent moves toward 1 as tags are processed', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('gfrm-gui-progress-');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final List<double> progressValues = <double>[];
      final StreamSubscription<DesktopRunSnapshot> sub = controller.snapshots.listen(
        (s) => progressValues.add(s.progressPercent),
      );
      addTearDown(sub.cancel);

      final session = await controller.startRun(
        DesktopRunStartRequest(
          sourceProvider: 'github',
          sourceUrl: 'https://github.com/acme/source',
          sourceToken: 'source-token',
          targetProvider: 'gitlab',
          targetUrl: 'https://gitlab.com/acme/target',
          targetToken: 'target-token',
          workdir: tempDir.path,
        ),
      );
      await session.completion;
      await Future<void>.delayed(Duration.zero);

      expect(progressValues, isNotEmpty);
      expect(progressValues.any((double progress) => progress > 0.0 && progress < 1.0), isTrue);
      expect(progressValues.last, 1.0);
    });

    test('resumes run with typed completion', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('gfrm-gui-resume-');
      final File tagsFile = File('${tempDir.path}/failed-tags.txt')..writeAsStringSync('v1.0.0\n');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final session = await controller.resumeRun(
        DesktopRunResumeRequest(
          sourceProvider: 'github',
          sourceUrl: 'https://github.com/acme/source',
          sourceToken: 'source-token',
          targetProvider: 'gitlab',
          targetUrl: 'https://gitlab.com/acme/target',
          targetToken: 'target-token',
          workdir: tempDir.path,
          tagsFile: tagsFile.path,
        ),
      );

      final completion = await session.completion;

      expect(completion.status, 'success');
      expect(completion.snapshot.sessionId, session.sessionId);
      expect(completion.snapshot.lifecycle, 'completed');
    });

    test('returns unsupported result for cancel', () async {
      final result = await controller.cancelActiveRun();

      expect(result.supported, isFalse);
      expect(result.message, contains('not available'));
    });
  });
}
