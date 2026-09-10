import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/completions_calculators_screen.dart';
import 'package:wellwerks/screens/sts_calculator_screen.dart';

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

  Future<void> pumpSts(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    await tester.pumpWidget(const MaterialApp(home: StsCalculatorScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('Build 307: STS Calculator appears directly below BTS Calculator',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    await tester.pumpWidget(
      const MaterialApp(home: CompletionsCalculatorsScreen()),
    );
    await tester.pumpAndSettle();

    final btsY = tester.getTopLeft(find.text('BTS Calculator')).dy;
    final stsY = tester.getTopLeft(find.text('STS Calculator')).dy;
    expect(btsY < stsY, isTrue);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Build 307: STS Calculator defaults to Coil Tubing inputs',
      (tester) async {
    await pumpSts(tester);

    expect(find.text('STS Calculator'), findsOneWidget);
    expect(find.text('Pipe Type'), findsOneWidget);
    expect(find.text('Coil Barrel Capacity (BBL)'), findsOneWidget);
    expect(find.text('Tubing OD'), findsOneWidget);
    expect(find.text('Casing OD'), findsOneWidget);
    expect(find.text('Casing Weight'), findsOneWidget);
    expect(find.text('Pump Rate (BBL/min)'), findsOneWidget);
    expect(find.text('Flowback Return Rate (BBL/min)'), findsOneWidget);
  });

  testWidgets('Build 307: switching to Stick Pipe swaps inputs', (
    tester,
  ) async {
    await pumpSts(tester);

    await tester.ensureVisible(find.text('Stick Pipe (Rig)'));
    await tester.tap(find.text('Stick Pipe (Rig)'));
    await tester.pumpAndSettle();

    expect(find.text('Coil Barrel Capacity (BBL)'), findsNothing);
    expect(find.text('Pipe OD'), findsOneWidget);
  });

  testWidgets('Build 307: Coil Tubing STS Time equals Pump Down + Return Time',
      (tester) async {
    await pumpSts(tester);

    // Default: Tubing 2-7/8" EUE OD 2.875, Casing 5-1/2" @ 15.5 lb/ft ID 4.950.
    await _enterField(tester, 'Coil Barrel Capacity (BBL)', '20');
    await _enterField(tester, 'Bit Depth (ft)', '10000');
    await _enterField(tester, 'Pump Rate (BBL/min)', '2');
    await _enterField(tester, 'Flowback Return Rate (BBL/min)', '2');

    await tester.ensureVisible(find.text('CALCULATE'));
    await tester.tap(find.text('CALCULATE'));
    await tester.pumpAndSettle();

    // Pump Down Time = 20 / 2 = 10.00 min
    // Annular Capacity = (4.950^2 - 2.875^2)/1029.4 * 10000 = 157.73 BBL
    // Return Time = 157.73 / 2 = 78.87 min
    // STS Time = 10 + 78.87 = 88.87 min -> 1 hr 29 min
    expect(find.text('STS TIME'), findsOneWidget);
    expect(find.textContaining('10.00'), findsWidgets);
    expect(find.textContaining('1 hr 29 min'), findsOneWidget);
    expect(find.text('START STS TIMER'), findsOneWidget);
  });

  testWidgets('Build 307: live STS timer starts, pauses, resumes, and resets',
      (tester) async {
    await pumpSts(tester);

    await _enterField(tester, 'Coil Barrel Capacity (BBL)', '10');
    await _enterField(tester, 'Bit Depth (ft)', '1000');
    await _enterField(tester, 'Pump Rate (BBL/min)', '5');
    await _enterField(tester, 'Flowback Return Rate (BBL/min)', '5');

    await tester.ensureVisible(find.text('CALCULATE'));
    await tester.tap(find.text('CALCULATE'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('START STS TIMER'));
    await tester.tap(find.text('START STS TIMER'));
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

    expect(find.text('START STS TIMER'), findsOneWidget);
  });
}
