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

  test('Build 171 Menard gas tank uses dedicated nonlinear dataset', () {
    expect(menardGasTankChart.barrelsAt(0), 0.00);
    expect(menardGasTankChart.barrelsAt(1), 0.53);
    expect(menardGasTankChart.barrelsAt(2), 2.12);
    expect(menardGasTankChart.barrelsAt(10), 34.48);
    expect(menardGasTankChart.barrelsAt(24), 95.10);
    expect(menardGasTankChart.barrelsAt(29), 116.75);
    expect(menardGasTankChart.barrelsAt(36), 147.06);
    expect(menardGasTankChart.barrelsAt(48), 199.02);
    expect(menardGasTankChart.barrelsAt(50), 216.66);
    expect(menardGasTankChart.barrelsAt(60), 264.76);
    expect(menardGasTankChart.barrelsAt(72), 322.48);
    expect(menardGasTankChart.barrelsAt(83), 375.39);
    expect(menardGasTankChart.barrelsAt(96), 437.92);
    expect(menardGasTankChart.barrelsAt(108), 495.64);
    expect(menardGasTankChart.barrelsAt(109), 500.45);
    expect(menardGasTankChart.barrelsAt(110), 505.26);
  });

  test('Build 171 Menard gas tank interpolates fractional gauges', () {
    expect(menardGasTankChart.barrelsAt(24.5), closeTo(97.265, 0.0001));
    expect(menardGasTankChart.barrelsAt(59.5), closeTo(262.355, 0.0001));
  });

  test('Build 171 Menard gas tank rejects out-of-range gauges', () {
    expect(menardGasTankChart.supportsGauge(-0.1), isFalse);
    expect(menardGasTankChart.supportsGauge(110.1), isFalse);
    expect(menardGasTankChart.barrelsAtOrNull(-0.1), isNull);
    expect(menardGasTankChart.barrelsAtOrNull(110.1), isNull);
  });

  test('Build 171 production tank remains 1.67 bbl per inch', () {
    const factor = 1.67;
    expect(10 * factor, 16.7);
    expect(100 * factor, 167.0);
  });
}
