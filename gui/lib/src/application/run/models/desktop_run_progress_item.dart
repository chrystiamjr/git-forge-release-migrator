final class DesktopRunProgressItem {
  const DesktopRunProgressItem({
    required this.kind,
    required this.tag,
    required this.status,
    required this.message,
    this.assetCount,
  });

  final String kind;
  final String tag;
  final String status;
  final String message;
  final int? assetCount;
}
