final class TimeUtils {
  const TimeUtils._();

  static String utcTimestamp() {
    final DateTime now = DateTime.now().toUtc();
    final String year = now.year.toString().padLeft(4, '0');
    final String month = now.month.toString().padLeft(2, '0');
    final String day = now.day.toString().padLeft(2, '0');
    final String hour = now.hour.toString().padLeft(2, '0');
    final String minute = now.minute.toString().padLeft(2, '0');
    final String second = now.second.toString().padLeft(2, '0');
    return '$year-$month-$day' 'T$hour:$minute:$second' 'Z';
  }
}
