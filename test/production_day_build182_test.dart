import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/utils/production_day.dart';

void main() {
  test('Build 182 production day 05:59 belongs to previous day', () {
    final value = productionDayFor(DateTime(2026, 7, 27, 5, 59));
    expect(value, DateTime(2026, 7, 26));
  });

  test('Build 182 production day 06:00 belongs to current day', () {
    final value = productionDayFor(DateTime(2026, 7, 27, 6, 0));
    expect(value, DateTime(2026, 7, 27));
  });

  test('Build 182 production day 23:59 belongs to current day', () {
    final value = productionDayFor(DateTime(2026, 7, 27, 23, 59));
    expect(value, DateTime(2026, 7, 27));
  });

  test('Build 182 production day 00:00 belongs to previous day', () {
    final value = productionDayFor(DateTime(2026, 7, 28, 0, 0));
    expect(value, DateTime(2026, 7, 27));
  });

  test('Build 182 production day 05:59 next day belongs to previous day', () {
    final value = productionDayFor(DateTime(2026, 7, 28, 5, 59));
    expect(value, DateTime(2026, 7, 27));
  });

  test('Build 182 production day 06:00 next day belongs to current day', () {
    final value = productionDayFor(DateTime(2026, 7, 28, 6, 0));
    expect(value, DateTime(2026, 7, 28));
  });
}
