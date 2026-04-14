final class RunStateReleaseSnapshot {
  const RunStateReleaseSnapshot({
    required this.tag,
    required this.status,
    required this.assetCount,
    required this.message,
  });

  final String tag;
  final String status;
  final int assetCount;
  final String message;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tag': tag,
      'status': status,
      'asset_count': assetCount,
      'message': message,
    };
  }
}
