import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/data/tank_charts.dart';
import 'package:wellwerks/screens/tank_charts_menu_screen.dart';

void main() {
  test('Build 308 SandX Beast uses the manufacturer lookup values', () {
    expect(sandXBeastChart.name, 'SandX Beast');
    expect(sandXBeastChart.points.length, 94);
    expect(sandXBeastChart.barrelsAt(1), 51.3);
    expect(sandXBeastChart.barrelsAt(94), 448.4);
    expect(sandXBeastChart.barrelsAt(1.5), closeTo(52.65, 0.001));
    expect(sandXBeastChart.barrelsAt(1.125), closeTo(51.6375, 0.001));
  });

  testWidgets('Build 308 SandX Beast appears in Tank Charts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TankChartsMenuScreen()));
    await tester.pumpAndSettle();

    expect(find.text('SandX Beast'), findsOneWidget);
    expect(
        find.text('SandX Beast manufacturer strapping chart'), findsOneWidget);
  });
}
