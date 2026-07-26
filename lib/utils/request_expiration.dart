/// Whether a pending appointment request has passed its requested end time.
/// Quote requests have no appointment date/time and do not expire by this rule.
bool isPendingRequestExpired(Map<String, dynamic> request, {DateTime? now}) {
  final status = (request['status'] ?? 'pending')
      .toString()
      .trim()
      .toLowerCase();
  if (status != 'pending' && status != 'waiting_for_approval') return false;
  final date = request['date']?.toString().trim();
  final time = (request['requestedTo'] ?? request['requestedFrom'])
      ?.toString()
      .trim();
  if (date == null || date.isEmpty || time == null || time.isEmpty) {
    return false;
  }

  final dateParts = date.split('-');
  final timeParts = time.split(':');
  if (dateParts.length != 3 || timeParts.length < 2) {
    return false;
  }
  final year = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final day = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null) {
    return false;
  }
  final deadline = DateTime(year, month, day, hour, minute);
  if (deadline.year != year ||
      deadline.month != month ||
      deadline.day != day ||
      deadline.hour != hour ||
      deadline.minute != minute) {
    return false;
  }
  return deadline.isBefore(now ?? DateTime.now());
}
