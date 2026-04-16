final class DesktopRunCountSummary {
  const DesktopRunCountSummary({
    required this.created,
    required this.wouldCreate,
    required this.skippedExisting,
    required this.failed,
  });

  const DesktopRunCountSummary.initial() : created = 0, wouldCreate = 0, skippedExisting = 0, failed = 0;

  final int created;
  final int wouldCreate;
  final int skippedExisting;
  final int failed;

  int get total => created + wouldCreate + skippedExisting + failed;
}
