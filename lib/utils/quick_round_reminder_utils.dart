int normalizeQuickRoundReminderMinute(int minute) {
  if (minute < 0) return 0;
  if (minute > 59) return 59;
  return minute;
}

String formatQuickRoundReminderMinute(int minute) {
  final normalized = normalizeQuickRoundReminderMinute(minute);
  return normalized.toString().padLeft(2, '0');
}

DateTime calculateNextQuickRoundReminder(DateTime now, int minute) {
  final normalizedMinute = normalizeQuickRoundReminderMinute(minute);
  final candidate = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    normalizedMinute,
  );

  if (candidate.isAfter(now)) {
    return candidate;
  }

  return candidate.add(const Duration(hours: 1));
}
