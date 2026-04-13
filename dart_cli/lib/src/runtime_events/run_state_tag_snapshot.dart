final class RunStateTagSnapshot {
  const RunStateTagSnapshot({
    required this.tag,
    required this.status,
    required this.message,
  });

  final String tag;
  final String status;
  final String message;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tag': tag,
      'status': status,
      'message': message,
    };
  }
}
