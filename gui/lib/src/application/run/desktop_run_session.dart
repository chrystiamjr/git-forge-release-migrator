import 'desktop_run_completion.dart';
import 'desktop_run_snapshot.dart';

final class DesktopRunSession {
  const DesktopRunSession({required this.sessionId, required this.initialSnapshot, required this.completion});

  final String sessionId;
  final DesktopRunSnapshot initialSnapshot;
  final Future<DesktopRunCompletion> completion;
}
