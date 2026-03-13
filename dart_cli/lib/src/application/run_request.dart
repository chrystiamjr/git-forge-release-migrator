import '../models/runtime_options.dart';

final class RunRequest {
  const RunRequest({
    required this.options,
  });

  final RuntimeOptions options;
}
