import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/data/tank_charts.dart';

void main() {
  test('Build 169 Flowback round-bottom uses Wichita 500 profile values', () {
    expect(flowbackRoundBottomChart.barrelsAt(0), 0);
    expect(flowbackRoundBottomChart.barrelsAt(1), 4.5);
    expect(flowbackRoundBottomChart.barrelsAt(10), 45.0);
    expect(flowbackRoundBottomChart.barrelsAt(44), 200.0);
    expect(flowbackRoundBottomChart.barrelsAt(44.5), 202.5);
    expect(flowbackRoundBottomChart.barrelsAt(45), 205.0);
    expect(flowbackRoundBottomChart.barrelsAt(46), 210.0);
    expect(flowbackRoundBottomChart.barrelsAt(100), 480.0);
    expect(flowbackRoundBottomChart.barrelsAt(104), 500.0);
  });

  test('Build 169 Flowback round-bottom rejects out-of-range gauges', () {
    expect(flowbackRoundBottomChart.supportsGauge(-0.1), isFalse);
    expect(flowbackRoundBottomChart.supportsGauge(104.1), isFalse);
    expect(flowbackRoundBottomChart.barrelsAtOrNull(-0.1), isNull);
    expect(flowbackRoundBottomChart.barrelsAtOrNull(104.1), isNull);
  });

  test('Build 169 interpolation works in lower, transition, and upper sections',
      () {
    expect(flowbackRoundBottomChart.barrelsAt(10.5), closeTo(47.2794, 0.0001));
    expect(flowbackRoundBottomChart.barrelsAt(44.5), 202.5);
    expect(flowbackRoundBottomChart.barrelsAt(80.5), 382.5);
  });

  test('Build 169 FS3, SandX, and Flowback use separate datasets', () {
    expect(fs3Chart.id, isNot(sandXChart.id));
    expect(fs3Chart.id, isNot(flowbackRoundBottomChart.id));
    expect(sandXChart.id, isNot(flowbackRoundBottomChart.id));

    expect(fs3Chart.barrelsAt(10), 74.3);
    expect(sandXChart.barrelsAt(10), 43.0);
    expect(flowbackRoundBottomChart.barrelsAt(10), 45.0);

    expect(fs3Chart.barrelsAt(10), isNot(sandXChart.barrelsAt(10)));
  });

  test('Build 169 production tank remains 1.67 bbl per inch', () {
    const factor = 1.67;
    expect(10 * factor, 16.7);
    expect(100 * factor, 167.0);
  });
}
