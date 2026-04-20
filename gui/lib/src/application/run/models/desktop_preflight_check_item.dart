final class DesktopPreflightCheckItem {
  const DesktopPreflightCheckItem({
    required this.code,
    required this.message,
    required this.status,
    this.hint,
    this.field,
  });

  final String code;
  final String message;
  final String status;
  final String? hint;
  final String? field;

  bool get isBlocking => status == 'error';
  bool get isWarning => status == 'warning';
}
