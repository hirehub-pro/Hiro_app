List<DateTime> generateMonthlyInstallmentDates({
  required DateTime firstDate,
  required int count,
}) {
  if (count < 1) {
    throw ArgumentError.value(count, 'count', 'Must be at least 1.');
  }

  return List<DateTime>.generate(count, (index) {
    final zeroBasedMonth = firstDate.month - 1 + index;
    final year = firstDate.year + zeroBasedMonth ~/ 12;
    final month = zeroBasedMonth % 12 + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day = firstDate.day.clamp(1, lastDayOfMonth);
    return DateTime(year, month, day);
  }, growable: false);
}
