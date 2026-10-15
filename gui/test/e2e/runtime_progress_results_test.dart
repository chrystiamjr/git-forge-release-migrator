// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ProviderRef;
import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_dart/src/application/preflight_service.dart';
import 'package:gfrm_dart/src/application/run_service.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/existing_release_info.dart';
import 'package:gfrm_dart/src/core/types/publish_release_input.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:gfrm_gui/src/app/gfrm_app.dart';
import 'package:gfrm_gui/src/app/navigation/app_router.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_completion.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_stat_card.dart';
import 'package:gfrm_gui/src/runtime/run/providers/desktop_run_controller_provider.dart';
import 'package:gfrm_gui/src/runtime/run/services/gfrm_desktop_run_controller.dart';

import '../support/run_service_fakes.dart';

const Duration _operationTimeout = Duration(seconds: 10);

void main() {
  late Directory directory;
  late _PausedTarget target;
  late GfrmDesktopRunController controller;
  DesktopRunSession? session;

  setUp(() {
    session = null;
    directory = Directory.systemTemp.createTempSync('gfrm-runtime-ui-');
    final ProviderRegistry registry = buildTestRegistry(
      releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0'), buildMinimalReleasePayload('v2.0.0')],
    );
    target = _PausedTarget(registry.get('gitlab'));
    registry.adapters['gitlab'] = target;
    final PreflightService preflight = PreflightService(settingsLoader: () => <String, dynamic>{});
    controller = GfrmDesktopRunController(
      logger: createSilentLogger(),
      runService: RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => registry,
        preflightService: preflight,
      ),
      preflightService: preflight,
      registryFactory: (_) => registry,
    );
  });

  tearDown(() async {
    target.releaseAll();
    await session?.completion.timeout(_operationTimeout);
    controller.dispose();
    directory.deleteSync(recursive: true);
  });

  for (final bool partialFailure in <bool>[false, true]) {
    final String outcome = partialFailure ? 'partial_failure' : 'success';
    testWidgets('real runtime drives progress through $outcome results and generated artifacts', (
      WidgetTester tester,
    ) async {
      target.failSecondRelease = partialFailure;
      final ProviderContainer container = await _openRuntime(tester, controller);
      session = await tester.runAsync(() => controller.startRun(_request(directory)));
      await _reach(tester, target.preflight);
      expect(find.text('Status: running'), findsOneWidget);
      expect(find.text('Phase: preflight'), findsOneWidget);
      expect(_count(tester, 'progress', 'tags', 'created'), '0');

      await _navigate(tester, container, '/results');
      expect(find.text('Migration in progress'), findsOneWidget);
      expect(find.text('Artifacts'), findsNothing);
      await _navigate(tester, container, '/progress');

      target.preflight.release();
      await _reach(tester, target.tags);
      expect(find.text('Phase: tags'), findsOneWidget);
      expect(_count(tester, 'progress', 'tags', 'created'), '1');
      expect(_count(tester, 'progress', 'releases', 'created'), '0');
      expect(find.text('v1.0.0'), findsOneWidget);

      target.tags.release();
      await _reach(tester, target.releases);
      expect(find.text('Phase: releases'), findsOneWidget);
      expect(_count(tester, 'progress', 'tags', 'created'), '2');
      expect(_count(tester, 'progress', 'releases', 'created'), '1');
      expect(_count(tester, 'progress', 'releases', 'failed'), '0');
      await _navigate(tester, container, '/results');
      expect(find.text('Migration in progress'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('run-results-outcome')), findsNothing);
      expect(find.text('Artifacts'), findsNothing);
      expect(find.text('Retry from the terminal'), findsNothing);
      await _navigate(tester, container, '/progress');

      final DesktopRunCompletion completion = (await tester.runAsync(() async {
        target.releases.release();
        return session!.completion.timeout(_operationTimeout);
      }))!;
      await tester.pumpAndSettle();
      expect(completion.status, outcome);
      expect(completion.exitCode, partialFailure ? 1 : 0);
      expect(find.text('Status: completed'), findsOneWidget);
      expect(find.text('Phase: completed'), findsOneWidget);
      expect(find.text('Outcome: $outcome'), findsOneWidget);
      expect(_count(tester, 'progress', 'releases', 'created'), partialFailure ? '1' : '2');
      expect(_count(tester, 'progress', 'releases', 'failed'), partialFailure ? '1' : '0');

      await _navigate(tester, container, '/results');
      expect(find.text('Status: completed'), findsOneWidget);
      expect(find.text('Outcome: $outcome'), findsOneWidget);
      expect(find.text('Total tags: 2'), findsOneWidget);
      expect(find.text('Failed tags: ${partialFailure ? 1 : 0}'), findsOneWidget);
      expect(_count(tester, 'results', 'tags', 'created'), '2');
      expect(_count(tester, 'results', 'releases', 'created'), partialFailure ? '1' : '2');
      expect(_count(tester, 'results', 'releases', 'failed'), partialFailure ? '1' : '0');
      _expectWrittenArtifacts(completion.snapshot);
      final Map<String, dynamic> summary =
          jsonDecode(File(completion.snapshot.artifacts.summaryPath).readAsStringSync()) as Map<String, dynamic>;
      expect(summary['schema_version'], 2);
      expect(summary['counts'], containsPair('tags_created', 2));
      expect(summary['counts'], containsPair('releases_created', partialFailure ? 1 : 2));
      expect(summary['counts'], containsPair('releases_failed', partialFailure ? 1 : 0));
      expect(summary['retry_command'], completion.snapshot.retryCommand);
      expect(
        File(completion.snapshot.artifacts.failedTagsPath).readAsLinesSync(),
        partialFailure ? <String>['v2.0.0'] : isEmpty,
      );
      if (partialFailure) {
        expect(find.text('release: v2.0.0'), findsOneWidget);
        expect(find.textContaining('Destination rejected v2.0.0'), findsOneWidget);
        expect(find.text(completion.snapshot.retryCommand), findsOneWidget);
        expect(completion.snapshot.retryCommand, startsWith('gfrm resume '));
      } else {
        expect(find.text('Failed items'), findsNothing);
        expect(find.text('Retry from the terminal'), findsNothing);
        expect(completion.snapshot.retryCommand, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('real preflight stop reaches both screens without migration or written artifacts', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _openRuntime(tester, controller);
    final DesktopRunCompletion completion = (await tester.runAsync(() async {
      session = await controller.startRun(_request(directory, targetToken: ''));
      return session!.completion.timeout(_operationTimeout);
    }))!;
    await tester.pumpAndSettle();
    expect(completion.status, 'validation_failure');
    expect(completion.exitCode, 1);
    expect(target.operations, isEmpty);
    expect(find.text('Status: failed'), findsOneWidget);
    expect(find.text('Phase: preflight'), findsOneWidget);
    expect(find.text('Outcome: validation_failure'), findsOneWidget);
    expect(find.text('Failure: Missing target token.'), findsOneWidget);
    expect(_count(tester, 'progress', 'tags', 'created'), '0');
    expect(_count(tester, 'progress', 'releases', 'created'), '0');

    await _navigate(tester, container, '/results');
    expect(find.text('Status: failed'), findsOneWidget);
    expect(find.text('Outcome: validation_failure'), findsOneWidget);
    expect(find.text('Phase: preflight'), findsOneWidget);
    expect(find.text('Code: missing-target-token'), findsOneWidget);
    expect(find.text('Missing target token.'), findsOneWidget);
    expect(find.text('Total tags: 0'), findsOneWidget);
    expect(find.text('Failed tags: 0'), findsOneWidget);
    expect(find.text('Retry from the terminal'), findsNothing);
    expect(completion.snapshot.canResume, isFalse);
    // RunResult reports planned paths even when startup stops before creating files.
    // Results labels these as reported paths; it does not promise file availability.
    expect(find.text('Paths reported by this run:'), findsOneWidget);
    for (final String path in _artifactPaths(completion.snapshot)) {
      expect(find.text(path), findsOneWidget);
      expect(File(path).existsSync(), isFalse);
    }
    expect(directory.listSync(recursive: true), isEmpty);
    expect(tester.takeException(), isNull);
  });
}

DesktopRunStartRequest _request(Directory directory, {String targetToken = 'target-token'}) => DesktopRunStartRequest(
  sourceProvider: 'github',
  sourceUrl: 'https://github.com/acme/source',
  sourceToken: 'source-token',
  targetProvider: 'gitlab',
  targetUrl: 'https://gitlab.com/acme/target',
  targetToken: targetToken,
  workdir: directory.path,
);

Future<ProviderContainer> _openRuntime(WidgetTester tester, GfrmDesktopRunController controller) async {
  tester.view.physicalSize = const Size(1280, 800);
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
  await _navigate(tester, container, '/progress');
  return container;
}

Future<void> _navigate(WidgetTester tester, ProviderContainer container, String path) async {
  container.read(appRouterProvider).go(path);
  await tester.pumpAndSettle();
}

Future<void> _reach(WidgetTester tester, _Milestone milestone) async {
  await tester.runAsync(() => milestone.reached.future.timeout(_operationTimeout));
  await tester.pumpAndSettle();
}

String _count(WidgetTester tester, String screen, String kind, String outcome) =>
    tester.widget<GfrmStatCard>(find.byKey(ValueKey<String>('run-$screen-$kind-$outcome'))).value;

List<String> _artifactPaths(DesktopRunSnapshot snapshot) => <String>[
  snapshot.artifacts.summaryPath,
  snapshot.artifacts.failedTagsPath,
  snapshot.artifacts.migrationLogPath,
];

void _expectWrittenArtifacts(DesktopRunSnapshot snapshot) {
  for (final String path in _artifactPaths(snapshot)) {
    expect(path, isNotEmpty);
    expect(find.text(path), findsOneWidget);
    expect(File(path).existsSync(), isTrue);
  }
}

final class _Milestone {
  final Completer<void> reached = Completer<void>();
  final Completer<void> _proceed = Completer<void>();

  Future<void> wait() async {
    if (!reached.isCompleted) {
      reached.complete();
    }
    await _proceed.future;
  }

  void release() {
    if (!_proceed.isCompleted) {
      _proceed.complete();
    }
  }
}

final class _PausedTarget extends ProviderAdapter {
  _PausedTarget(this.delegate);

  final ProviderAdapter delegate;
  final _Milestone preflight = _Milestone();
  final _Milestone tags = _Milestone();
  final _Milestone releases = _Milestone();
  final List<String> operations = <String>[];
  bool failSecondRelease = false;

  void releaseAll() {
    preflight.release();
    tags.release();
    releases.release();
  }

  @override
  String get name => delegate.name;

  @override
  ProviderRef parseUrl(String url) => delegate.parseUrl(url);

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) => delegate.toCanonicalRelease(payload);

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async {
    operations.add('list-tags');
    return delegate.listTags(ref, token);
  }

  @override
  Future<bool> commitExists(ProviderRef ref, String token, String sha) async {
    operations.add('commit-exists');
    await preflight.wait();
    return delegate.commitExists(ref, token, sha);
  }

  @override
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    operations.add('tag-exists:$tag');
    return delegate.tagExists(ref, token, tag);
  }

  @override
  Future<void> createTagForMigration(
    ProviderRef ref,
    String token,
    String tag,
    String sha,
    CanonicalRelease canonical,
  ) async {
    operations.add('create-tag:$tag');
    if (tag == 'v2.0.0') {
      await tags.wait();
    }
    await delegate.createTagForMigration(ref, token, tag, sha, canonical);
  }

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(ProviderRef ref, String token, String tag, int expectedLinkAssets) =>
      delegate.existingReleaseInfo(ref, token, tag, expectedLinkAssets);

  @override
  Future<String> publishRelease(PublishReleaseInput input) async {
    operations.add('publish-release:${input.tag}');
    if (input.tag == 'v2.0.0') {
      await releases.wait();
      if (failSecondRelease) {
        throw Exception('Destination rejected v2.0.0');
      }
    }
    return delegate.publishRelease(input);
  }
}
