String utcTimestamp() {
  final DateTime now = DateTime.now().toUtc();
  final String y = now.year.toString().padLeft(4, '0');
  final String m = now.month.toString().padLeft(2, '0');
  final String d = now.day.toString().padLeft(2, '0');
  final String hh = now.hour.toString().padLeft(2, '0');
  final String mm = now.minute.toString().padLeft(2, '0');
  final String ss = now.second.toString().padLeft(2, '0');
  return '$y-$m-$d' 'T$hh:$mm:$ss' 'Z';
}
