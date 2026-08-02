import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/services/rate_calculator_session_service.dart';

RateCalculatorSession _session({
  required String calculatorId,
  required String startGauge,
  required int updatedAtMs,
}) {
  return RateCalculatorSession(
    calculatorId: calculatorId,
    calculatorTitle: 'FS3 Tank',
    chartId: 'fs3',
    usesChart: true,
    startGauge: startGauge,
    endGauge: '20',
    minutes: '5',
    factor: '1.67',
    rateDisplayUnit: 'bbl_min',
    rateLogEnabled: true,
    rateLogExpanded: false,
    bblPerMin: 12.3,
    bblPerHr: 738,
    bblPerDay: 17712,
    error: null,
    timerFinished: false,
    remainingSeconds: 300,
    thirtySecondAlertShown: false,
    timerStartedAtMs: null,
    timerEndsAtMs: null,
    timerDurationSeconds: null,
    rateLogEntries: const <RateCalculatorSessionLogEntry>[],
    useLiveClock: false,
    liveClockElapsedSeconds: 0,
    updatedAtMs: updatedAtMs,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RateCalculatorSessionService.instance.resetForTesting();
  });

  test('stores separate sessions for the same calculator', () async {
    final service = RateCalculatorSessionService.instance;
    await service.ensureInitialized();

    await service.saveSession(
      _session(calculatorId: 'fs3', startGauge: '10', updatedAtMs: 1),
      sessionKey: 'fs3-instance-a',
    );
    await service.saveSession(
      _session(calculatorId: 'fs3', startGauge: '15', updatedAtMs: 2),
      sessionKey: 'fs3-instance-b',
    );

    expect(service.sessionForInstance('fs3-instance-a')?.startGauge, '10');
    expect(service.sessionForInstance('fs3-instance-b')?.startGauge, '15');
    expect(service.sessionForCalculator('fs3')?.startGauge, '15');

    await service.clearSession('fs3-instance-a');

    expect(service.sessionForInstance('fs3-instance-a'), isNull);
    expect(service.sessionForInstance('fs3-instance-b'), isNotNull);
  });
}
