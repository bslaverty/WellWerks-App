import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/screens/completions_calculators_screen.dart';

void main() {
  testWidgets('Build 257 shows Pump Rate Calculator above Gas Accum',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CompletionsCalculatorsScreen()),
    );
    await tester.pumpAndSettle();

    final pumpFinder = find.text('Pump Rate Calculator');
    final gasFinder = find.text('Gas Accum Calculator');

    expect(pumpFinder, findsOneWidget);
    expect(gasFinder, findsOneWidget);

    final pumpY = tester.getTopLeft(pumpFinder).dy;
    final gasY = tester.getTopLeft(gasFinder).dy;
    expect(pumpY < gasY, isTrue);

    expect(find.text('Bottoms Up Calculator'), findsOneWidget);
    expect(find.text('Multiple Choke Calculator'), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Conversion Calculator'),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Conversion Calculator'), findsOneWidget);
    expect(find.text('Chlorides Calculator'), findsOneWidget);
  });
}
