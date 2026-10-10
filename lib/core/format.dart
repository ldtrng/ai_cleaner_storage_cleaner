String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var i = 0;
  while (value >= 1000 && i < units.length - 1) {
    value /= 1000;
    i++;
  }
  final digits = i <= 1 ? 0 : (value >= 100 ? 0 : decimals);
  return '${value.toStringAsFixed(digits)} ${units[i]}';
}

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String formatDuration(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  if (d.inHours > 0) {
    return '${d.inHours}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String formatMonthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String timeAgo(int epochMs) {
  if (epochMs <= 0) return 'Not in use';
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
  );
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${plural(diff.inMinutes, 'minute')} ago';
  if (diff.inDays < 1) return '${plural(diff.inHours, 'hour')} ago';
  return '${plural(diff.inDays, 'day')} ago';
}
