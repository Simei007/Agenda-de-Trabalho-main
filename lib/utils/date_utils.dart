DateTime dateOnly(DateTime day) {
  return DateTime(day.year, day.month, day.day);
}

String dayKey(DateTime day) {
  final year = day.year.toString().padLeft(4, '0');
  final month = day.month.toString().padLeft(2, '0');
  final monthDay = day.day.toString().padLeft(2, '0');
  return '$year-$month-$monthDay';
}

DateTime? parseDayKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }

  return DateTime(year, month, day);
}
