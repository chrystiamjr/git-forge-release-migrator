import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/run/desktop_run_controller.dart';
import '../../application/run/desktop_run_snapshot.dart';
import 'gfrm_desktop_run_controller.dart';

part 'desktop_run_controller_provider.g.dart';

typedef DesktopRunControllerFactory = DesktopRunController Function();

@Riverpod(keepAlive: true)
DesktopRunControllerFactory desktopRunControllerFactory(Ref ref) {
  return GfrmDesktopRunController.defaults;
}

@Riverpod(keepAlive: true)
DesktopRunController desktopRunController(Ref ref) {
  final DesktopRunController controller = ref.watch(desktopRunControllerFactoryProvider)();
  ref.onDispose(controller.dispose);
  return controller;
}

@Riverpod(keepAlive: true)
Stream<DesktopRunSnapshot> desktopRunSnapshots(Ref ref) {
  final DesktopRunController controller = ref.watch(desktopRunControllerProvider);
  return controller.snapshots;
}
