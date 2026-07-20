import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/rate_calculator_screen.dart';

Future<void> _pumpRateCalculator(
  WidgetTester tester,
  RateCalculatorConfig config,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.binding.setSurfaceSize(const Size(1280, 1800));
  await tester.pumpWidget(
    MaterialApp(home: RateCalculatorScreen(config: config)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapGaugeField(WidgetTester tester, String label) async {
  final fieldFinder = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  await tester.ensureVisible(fieldFinder.first);
  await tester.pumpAndSettle();
  await tester.tap(fieldFinder.first);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String keyLabel) async {
  await tester.tap(find.widgetWithText(OutlinedButton, keyLabel).first);
  await tester.pumpAndSettle();
}

Future<void> _enterIntegerGauge(
  WidgetTester tester, {
  required String label,
  required String value,
}) async {
  await _tapGaugeField(tester, label);
  for (final ch in value.split('')) {
    await _tapKey(tester, ch);
  }
}

void main() {
  testWidgets(
      'Build 169 keypad always shows Calculate Rate after result/reset state',
      (WidgetTester tester) async {
    await _pumpRateCalculator(
      tester,
      const RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
    );

    await _enterIntegerGauge(tester, label: 'Starting Gauge', value: '10');
    expect(find.widgetWithText(FilledButton, 'Calculate Rate'), findsOneWidget);

    await _enterIntegerGauge(tester, label: 'Ending Gauge', value: '20');
    await tester.tap(find.widgetWithText(FilledButton, 'Calculate Rate'));
    await tester.pumpAndSettle();

    expect(find.text('Results'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'RESET'), findsOneWidget);

    await _tapGaugeField(tester, 'Starting Gauge');
    expect(find.widgetWithText(FilledButton, 'Calculate Rate'), findsOneWidget);

    await _tapGaugeField(tester, 'Ending Gauge');
    expect(find.widgetWithText(FilledButton, 'Calculate Rate'), findsOneWidget);
  });

  testWidgets('Build 169 Done closes keypad without calculating',
      (WidgetTester tester) async {
    await _pumpRateCalculator(
      tester,
      const RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
    );

    await _enterIntegerGauge(tester, label: 'Starting Gauge', value: '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(find.text('Gauge Keypad • Starting Gauge'), findsNothing);
    expect(find.text('Results'), findsNothing);
  });

  testWidgets('Build 169 second calculation works without pressing RESET',
      (WidgetTester tester) async {
    await _pumpRateCalculator(
      tester,
      const RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
    );

    await tester.tap(find.text('Rate Log').first);
    await tester.pumpAndSettle();
    await _enterIntegerGauge(tester, label: 'Starting Gauge', value: '10');
    await _enterIntegerGauge(tester, label: 'Ending Gauge', value: '20');
    await tester.tap(find.widgetWithText(FilledButton, 'Calculate Rate'));
    await tester.pumpAndSettle();
    expect(find.text('Rate Log (1)'), findsOneWidget);

    await _tapGaugeField(tester, 'Starting Gauge');
    await tester.tap(find.widgetWithText(TextButton, 'CLR').first);
    await tester.pumpAndSettle();
    await _tapKey(tester, '1');
    await _tapKey(tester, '0');

    await _tapGaugeField(tester, 'Ending Gauge');
    await tester.tap(find.widgetWithText(TextButton, 'CLR').first);
    await tester.pumpAndSettle();
    await _tapKey(tester, '5');
    await _tapKey(tester, '0');

    await tester.tap(find.widgetWithText(FilledButton, 'Calculate Rate'));
    await tester.pumpAndSettle();

    expect(find.text('Rate Log (2)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'RESET'), findsOneWidget);
  });

  testWidgets('Build 169 rejects out-of-range round-bottom gauges',
      (WidgetTester tester) async {
    await _pumpRateCalculator(
      tester,
      const RateCalculatorConfig.chart(
        'Round Bottom',
        'flowback_round_bottom',
      ),
    );

    await _enterIntegerGauge(tester, label: 'Starting Gauge', value: '0');
    await _enterIntegerGauge(tester, label: 'Ending Gauge', value: '105');

    await tester.tap(find.widgetWithText(FilledButton, 'Calculate Rate'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Gauge reading is outside the supported Round Bottom chart.',
      ),
      findsOneWidget,
    );
  });
}
