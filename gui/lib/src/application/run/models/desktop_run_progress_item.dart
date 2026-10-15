final class DesktopRunProgressItem {
  static const String _failedStatus = 'failed';

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

  bool get isFailed => status == _failedStatus;
}
