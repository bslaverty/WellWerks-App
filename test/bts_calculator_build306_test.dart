import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/bts_calculator_screen.dart';

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final finder = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  await tester.ensureVisible(finder.first);
  await tester.enterText(finder.first, value);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpBts(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2000));
    await tester.pumpWidget(const MaterialApp(home: BtsCalculatorScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('Build 306: BTS Calculator renamed with updated labels',
      (tester) async {
    await pumpBts(tester);

    expect(find.text('BTS Calculator'), findsOneWidget);
    expect(find.text('Tubing OD'), findsOneWidget);
    expect(find.text('Casing OD'), findsOneWidget);
    expect(find.text('Casing Weight'), findsOneWidget);
    expect(find.text('Flowback Return Rate (BBL/min)'), findsOneWidget);
    expect(find.text('Bit Depth (ft)'), findsOneWidget);
  });

  testWidgets(
      'Build 306: casing selection auto-resolves ID and BTS time calculates',
      (tester) async {
    await pumpBts(tester);

    // Default: Tubing 2-7/8" EUE (2.875 OD), Casing 5-1/2" @ 15.5 lb/ft.
    expect(find.textContaining('Casing ID: 4.950'), findsOneWidget);

    await _enterField(tester, 'Bit Depth (ft)', '10000');
    await _enterField(tester, 'Flowback Return Rate (BBL/min)', '2');

    await tester.ensureVisible(find.text('CALCULATE'));
    await tester.tap(find.text('CALCULATE'));
    await tester.pumpAndSettle();

    // annularCapacity = (4.950^2 - 2.875^2)/1029.4 = 0.015773...
    // annularVolume = capacity * 10000 = 157.73...
    // btsMinutes = volume / 2 = 78.87... -> 1 hr 19 min
    expect(find.text('BTS TIME'), findsOneWidget);
    expect(find.textContaining('1 hr 19 min'), findsOneWidget);
    expect(find.text('START BTS TIMER'), findsOneWidget);
  });

  testWidgets('Build 306: live BTS timer starts, pauses, resumes, and resets',
      (tester) async {
    await pumpBts(tester);

    await _enterField(tester, 'Bit Depth (ft)', '1000');
    await _enterField(tester, 'Flowback Return Rate (BBL/min)', '5');

    await tester.ensureVisible(find.text('CALCULATE'));
    await tester.tap(find.text('CALCULATE'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('START BTS TIMER'));
    await tester.tap(find.text('START BTS TIMER'));
    await tester.pumpAndSettle();

    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('START BTS TIMER'), findsOneWidget);
  });
}
