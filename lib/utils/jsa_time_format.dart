import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final DateFormat _jsaTimeFormatter = DateFormat('h:mm a');

String formatJsaTime(TimeOfDay time) {
  return _jsaTimeFormatter.format(
    DateTime(2000, 1, 1, time.hour, time.minute),
  );
}

TimeOfDay? parseJsaTime(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }

  for (final pattern in const ['h:mm a', 'hh:mm a', 'H:mm', 'HH:mm']) {
    try {
      final parsed = DateFormat(pattern).parseStrict(trimmed);
      return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
    } catch (_) {
      continue;
    }
  }

  final amPmMatch =
      RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])$').firstMatch(trimmed);
  if (amPmMatch != null) {
    final hour = int.tryParse(amPmMatch.group(1) ?? '');
    final minute = int.tryParse(amPmMatch.group(2) ?? '0') ?? 0;
    final period = (amPmMatch.group(3) ?? '').toUpperCase();
    if (hour != null && hour >= 1 && hour <= 12 && minute >= 0 && minute < 60) {
      final hour24 = period == 'PM' ? (hour % 12) + 12 : (hour % 12);
      return TimeOfDay(hour: hour24, minute: minute);
    }
  }

  final numericMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
  if (numericMatch != null) {
    final hour = int.tryParse(numericMatch.group(1) ?? '');
    final minute = int.tryParse(numericMatch.group(2) ?? '');
    if (hour != null &&
        minute != null &&
        hour >= 0 &&
        hour < 24 &&
        minute >= 0 &&
        minute < 60) {
      return TimeOfDay(hour: hour, minute: minute);
    }
  }

  return null;
}

String formatStoredJsaTime(String raw) {
  final parsed = parseJsaTime(raw);
  return parsed == null ? raw.trim() : formatJsaTime(parsed);
}
