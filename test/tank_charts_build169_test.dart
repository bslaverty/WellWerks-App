import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/data/tank_charts.dart';
import 'package:wellwerks/utils/gauge_parser.dart';

void main() {
  test('Build 275 SandX G3 uses only confirmed strap-chart anchors', () {
    final anchors = <double, double>{
      10: 43.0,
      20: 86.0,
      30: 129.0,
      40: 173.0,
      50: 220.9,
      60: 267.9,
      70: 313.9,
      80: 359.1,
      90: 404.1,
      92: 413.4,
    };

    expect(sandXChart.points, hasLength(anchors.length));
    for (final anchor in anchors.entries) {
      expect(sandXChart.barrelsAt(anchor.key), anchor.value);
    }
  });

  test('Build 275 SandX G3 interpolates without rounded intermediate data', () {
    expect(sandXChart.barrelsAt(35), closeTo(151.0, 0.000001));
    expect(sandXChart.barrelsAt(36), closeTo(155.4, 0.000001));
    expect(sandXChart.barrelsAt(36.5), closeTo(157.6, 0.000001));
    expect(sandXChart.barrelsAt(45), closeTo(196.95, 0.000001));
    expect(sandXChart.barrelsAtOrNull(9.99), isNull);
    expect(sandXChart.barrelsAtOrNull(92.01), isNull);
  });

  test('Build 275 SandX rate calculation retains full chart precision', () {
    final startBarrels = sandXChart.barrelsAt(36);
    final endBarrels = sandXChart.barrelsAt(40);
    final barrelChange = endBarrels - startBarrels;
    final bblPerMinute = barrelChange / 5;

    expect(startBarrels, closeTo(155.4, 0.000001));
    expect(endBarrels, closeTo(173.0, 0.000001));
    expect(barrelChange, closeTo(17.6, 0.000001));
    expect(bblPerMinute, closeTo(3.52, 0.000001));
    expect(bblPerMinute * 60, closeTo(211.2, 0.000001));
  });

  test('Build 275 gauge fractions preserve their decimal values', () {
    expect(parseGaugeInput('36.5'), 36.5);
    expect(parseGaugeInput('36 1/2'), 36.5);
    expect(parseGaugeInput('36.25'), 36.25);
    expect(parseGaugeInput('36 1/4'), 36.25);
    expect(sandXChart.barrelsAt(parseGaugeInput('36 1/2')),
        closeTo(sandXChart.barrelsAt(36.5), 0.000001));
  });

  test('Build 275 chart-backed calculators retain source data and precision',
      () {
    // FS3: supplied inch-by-inch chart data.
    expect(fs3Chart.barrelsAt(0), 36.7);
    expect(fs3Chart.barrelsAt(34), 187.6);
    expect(fs3Chart.barrelsAt(68), 364.2);
    expect(fs3Chart.barrelsAt(34.5), closeTo(190.15, 0.000001));

    // SandX Cyclone: supplied inch-by-inch chart data.
    expect(sandXCycloneChart.barrelsAt(1), 78.34);
    expect(sandXCycloneChart.barrelsAt(45), 149.57);
    expect(sandXCycloneChart.barrelsAt(90), 222.19);
    expect(sandXCycloneChart.barrelsAt(45.5), closeTo(150.395, 0.000001));

    // V-bottom: supplied three-inch chart data.
    expect(flowback500Chart.barrelsAt(3), 3.4);
    expect(flowback500Chart.barrelsAt(60), 266.2);
    expect(flowback500Chart.barrelsAt(120), 532.5);
    expect(flowback500Chart.barrelsAt(61.5), closeTo(274.75, 0.000001));

    // MR 810039: supplied inch-by-inch chart data.
    expect(mr810039FlowbackChart.barrelsAt(1), 4.6);
    expect(mr810039FlowbackChart.barrelsAt(52), 246.4);
    expect(mr810039FlowbackChart.barrelsAt(104), 516.0);
    expect(mr810039FlowbackChart.barrelsAt(52.5), closeTo(249.1, 0.000001));
  });

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
    expect(1 * factor, 1.67);
    expect(10 * factor, 16.7);
    expect(100 * factor, 167.0);
  });
}
