import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/rate_calculator_screen.dart';
import 'package:wellwerks/services/rate_calculator_session_service.dart';
import 'package:wellwerks/services/rate_timer_service.dart';

Finder _gaugeField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> _pumpCalculator(
  WidgetTester tester,
  RateCalculatorConfig config,
) async {
  await tester.pumpWidget(
    MaterialApp(home: RateCalculatorScreen(config: config)),
  );
  await tester.pumpAndSettle();
}

Future<void> _seedActiveFs3SessionWithTimer() async {
  final sessionService = RateCalculatorSessionService.instance;
  sessionService.resetForTesting();
  await sessionService.ensureInitialized();

  final now = DateTime.now();
  final session = RateCalculatorSession(
    calculatorId: 'fs3',
    calculatorTitle: 'FS3 Tank',
    chartId: 'fs3',
    usesChart: true,
    startGauge: '42.0',
    endGauge: '43.5',
    minutes: '5',
    factor: '1.67',
    rateDisplayUnit: 'bbl_min',
    rateLogEnabled: true,
    rateLogExpanded: true,
    bblPerMin: 30.1,
    bblPerHr: 1806,
    bblPerDay: 43344,
    error: null,
    timerFinished: false,
    remainingSeconds: 240,
    thirtySecondAlertShown: false,
    timerStartedAtMs:
        now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    timerEndsAtMs: now.add(const Duration(minutes: 4)).millisecondsSinceEpoch,
    timerDurationSeconds: 300,
    rateLogEntries: const [
      RateCalculatorSessionLogEntry(
        timestampMs: 1730000000000,
        rateValue: 30.1,
        rateUnit: 'BBL/min',
        selected: true,
      ),
    ],
    useLiveClock: false,
    liveClockElapsedSeconds: 0,
    updatedAtMs: now.millisecondsSinceEpoch,
  );
  await sessionService.saveSession(session, setActive: true);

  final timerService = RateTimerService();
  final timer = await timerService.createState(
    calculatorId: 'fs3',
    calculatorTitle: 'FS3 Tank',
    wellOrJob: 'Well A',
    durationSeconds: 300,
  );
  final activeTimer = timer.copyWith(
    startedAtMs:
        now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    endsAtMs: now.add(const Duration(minutes: 4)).millisecondsSinceEpoch,
  );
  await timerService.saveActiveTimer(activeTimer);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RateCalculatorSessionService.instance.resetForTesting();
  });

  testWidgets('Build 206 restores active timer session after leaving screen',
      (tester) async {
    await _seedActiveFs3SessionWithTimer();

    await _pumpCalculator(
      tester,
      const RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
    );

    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();

    await _pumpCalculator(
      tester,
      const RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
    );

    final startTextField =
        tester.widget<TextField>(_gaugeField('Starting Gauge').first);
    final endTextField =
        tester.widget<TextField>(_gaugeField('Ending Gauge').first);
    expect(startTextField.controller?.text, '42.0');
    expect(endTextField.controller?.text, '43.5');
    expect(find.widgetWithText(OutlinedButton, 'Stop Timer'), findsOneWidget);
  });

  testWidgets('Build 206 opening another calculator reattaches active session',
      (tester) async {
    await _seedActiveFs3SessionWithTimer();

    await _pumpCalculator(
      tester,
      const RateCalculatorConfig.chart('SandX G3', 'sandx'),
    );

    expect(find.text('FS3 Tank'), findsOneWidget);
    expect(find.text('SandX G3'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Stop Timer'), findsOneWidget);
  });
}
