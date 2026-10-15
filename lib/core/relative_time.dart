String relativeTimeLabel(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(time);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24 && n.day == time.day) return '${diff.inHours}h ago';
  final yesterday =
      DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
  final day = DateTime(time.year, time.month, time.day);
  if (day == yesterday) return 'Yesterday';
  const months = [
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
  return '${months[time.month - 1]} ${time.day}';
}
