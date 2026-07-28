DateTime productionDayFor(DateTime timestamp, {int rolloverHour = 6}) {
  final local = timestamp.toLocal();
  final shifted = local.hour < rolloverHour
      ? local.subtract(const Duration(days: 1))
      : local;
  return DateTime(shifted.year, shifted.month, shifted.day);
}

String productionDayKey(DateTime timestamp, {int rolloverHour = 6}) {
  final day = productionDayFor(timestamp, rolloverHour: rolloverHour);
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}
