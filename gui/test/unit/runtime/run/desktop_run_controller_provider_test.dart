import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_gui/src/application/run/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/desktop_run_action_result.dart';
import 'package:gfrm_gui/src/application/run/desktop_run_controller.dart';
import 'package:gfrm_gui/src/application/run/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/application/run/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/runtime/run/desktop_run_controller_provider.dart';

void main() {
  group('desktop run controller providers', () {
    test('creates controller from factory provider and disposes it', () {
      final _FakeDesktopRunController fakeController = _FakeDesktopRunController();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          desktopRunControllerFactoryProvider.overrideWith((ref) {
            return () => fakeController;
          }),
        ],
      );

      final controller = container.read(desktopRunControllerProvider);

      expect(controller, same(fakeController));

      container.dispose();

      expect(fakeController.disposeCalled, isTrue);
    });

    test('relays snapshot stream through stream provider', () async {
      final _FakeDesktopRunController fakeController = _FakeDesktopRunController();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          desktopRunControllerFactoryProvider.overrideWith((ref) {
            return () => fakeController;
          }),
        ],
      );
      addTearDown(container.dispose);

      final List<AsyncValue<DesktopRunSnapshot>> states = <AsyncValue<DesktopRunSnapshot>>[];
      final ProviderSubscription<AsyncValue<DesktopRunSnapshot>> subscription = container.listen(
        desktopRunSnapshotsProvider,
        (previous, next) {
          states.add(next);
        },
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      fakeController.emit(const DesktopRunSnapshot.initial(sessionId: 'session-1'));
      await Future<void>.delayed(Duration.zero);

      expect(states.last.requireValue.sessionId, 'session-1');
    });
  });
}

final class _FakeDesktopRunController implements DesktopRunController {
  final StreamController<DesktopRunSnapshot> _controller = StreamController<DesktopRunSnapshot>.broadcast();

  bool disposeCalled = false;

  @override
  DesktopRunSnapshot currentSnapshot = const DesktopRunSnapshot.initial();

  @override
  Stream<DesktopRunSnapshot> get snapshots => _controller.stream;

  void emit(DesktopRunSnapshot snapshot) {
    currentSnapshot = snapshot;
    _controller.add(snapshot);
  }

  @override
  Future<DesktopPreflightSummary> evaluatePreflight(DesktopPreflightRequest request) async {
    return const DesktopPreflightSummary.initial();
  }

  @override
  Future<DesktopRunSession> resumeRun(DesktopRunResumeRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<DesktopRunSession> startRun(DesktopRunStartRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<DesktopRunActionResult> cancelActiveRun() async {
    return const DesktopRunActionResult(supported: false, message: 'unsupported');
  }

  @override
  void dispose() {
    disposeCalled = true;
    unawaited(_controller.close());
  }
}
