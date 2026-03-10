enum LoggerPrefix {
  info,
  warning,
  error,
}

extension LoggerPrefixExtension on LoggerPrefix {
  String get label {
    switch (this) {
      case LoggerPrefix.info:
        return 'INFO';
      case LoggerPrefix.warning:
        return 'WARN';
      case LoggerPrefix.error:
        return 'ERROR';
    }
  }
}
