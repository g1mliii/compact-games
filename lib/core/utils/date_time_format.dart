const List<String> _shortMonthNames = <String>[
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

String formatLocalTimestampMinutes(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

String? formatLocalTimestampMinutesOrNull(DateTime? value) {
  if (value == null) {
    return null;
  }
  return formatLocalTimestampMinutes(value);
}

String formatLocalMonthDayTime(DateTime value) {
  final local = value.toLocal();
  final month = _shortMonthNames[local.month - 1];
  final day = local.day;
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month $day, $hour:$minute';
}

String? formatLocalMonthDayTimeOrNull(DateTime? value) {
  if (value == null) {
    return null;
  }
  return formatLocalMonthDayTime(value);
}
