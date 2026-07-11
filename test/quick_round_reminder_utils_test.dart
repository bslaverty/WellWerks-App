import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/utils/quick_round_reminder_utils.dart';

void main() {
  group('quick round reminder minute formatting', () {
    test('formats minute 00 with leading zero', () {
      expect(formatQuickRoundReminderMinute(0), '00');
    });

    test('formats minute 59', () {
      expect(formatQuickRoundReminderMinute(59), '59');
    });

    test('formats minute 09 with leading zero', () {
      expect(formatQuickRoundReminderMinute(9), '09');
    });
  });

  group('calculate next quick round reminder', () {
    test('uses same hour when now is before selected minute', () {
      final now = DateTime(2026, 7, 11, 5, 10);
      final next = calculateNextQuickRoundReminder(now, 37);
      expect(next, DateTime(2026, 7, 11, 5, 37));
    });

    test('uses next hour when now is after selected minute', () {
      final now = DateTime(2026, 7, 11, 5, 45);
      final next = calculateNextQuickRoundReminder(now, 37);
      expect(next, DateTime(2026, 7, 11, 6, 37));
    });

    test('uses next hour when now is at same minute with seconds', () {
      final now = DateTime(2026, 7, 11, 5, 59, 30);
      final next = calculateNextQuickRoundReminder(now, 59);
      expect(next, DateTime(2026, 7, 11, 6, 59));
    });

    test('accepts minute 00', () {
      final now = DateTime(2026, 7, 11, 5, 0, 1);
      final next = calculateNextQuickRoundReminder(now, 0);
      expect(next, DateTime(2026, 7, 11, 6, 0));
    });

    test('accepts minute 59', () {
      final now = DateTime(2026, 7, 11, 5, 58, 59);
      final next = calculateNextQuickRoundReminder(now, 59);
      expect(next, DateTime(2026, 7, 11, 5, 59));
    });
  });
}
