class TankPoint {
  final double inches;
  final double barrels;
  const TankPoint(this.inches, this.barrels);
}

class TankChart {
  final String id;
  final String name;
  final List<TankPoint> points;
  const TankChart({required this.id, required this.name, required this.points});

  List<TankPoint> get _sortedPoints {
    final sorted = List<TankPoint>.from(points)
      ..sort((a, b) => a.inches.compareTo(b.inches));
    return sorted;
  }

  double get minInches {
    if (points.isEmpty) return 0;
    return _sortedPoints.first.inches;
  }

  double get maxInches {
    if (points.isEmpty) return 0;
    return _sortedPoints.last.inches;
  }

  bool supportsGauge(double inches) {
    if (points.isEmpty) return false;
    return inches >= minInches && inches <= maxInches;
  }

  double? barrelsAtOrNull(double inches) {
    if (!supportsGauge(inches)) return null;
    final sorted = _sortedPoints;
    if (inches == sorted.first.inches) return sorted.first.barrels;
    if (inches == sorted.last.inches) return sorted.last.barrels;

    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (inches >= a.inches && inches <= b.inches) {
        final span = b.inches - a.inches;
        if (span == 0) return a.barrels;
        final percent = (inches - a.inches) / span;
        return a.barrels + ((b.barrels - a.barrels) * percent);
      }
    }

    return null;
  }

  double barrelsAt(double inches) {
    if (points.isEmpty) return 0;
    final sorted = _sortedPoints;
    if (inches <= sorted.first.inches) return sorted.first.barrels;
    if (inches >= sorted.last.inches) return sorted.last.barrels;
    return barrelsAtOrNull(inches) ?? 0;
  }
}

const fs3Chart = TankChart(
  id: 'fs3',
  name: 'FS3 Tank',
  points: [
    TankPoint(0, 36.7),
    TankPoint(1, 39.9),
    TankPoint(2, 43.2),
    TankPoint(3, 46.7),
    TankPoint(4, 50.3),
    TankPoint(5, 54.0),
    TankPoint(6, 57.9),
    TankPoint(7, 61.8),
    TankPoint(8, 65.9),
    TankPoint(9, 70.0),
    TankPoint(10, 74.3),
    TankPoint(11, 78.6),
    TankPoint(12, 83.0),
    TankPoint(13, 87.5),
    TankPoint(14, 92.0),
    TankPoint(15, 96.5),
    TankPoint(16, 101.1),
    TankPoint(17, 105.7),
    TankPoint(18, 110.3),
    TankPoint(19, 115.0),
    TankPoint(20, 119.7),
    TankPoint(21, 124.4),
    TankPoint(22, 129.2),
    TankPoint(23, 134.0),
    TankPoint(24, 138.7),
    TankPoint(25, 143.5),
    TankPoint(26, 148.4),
    TankPoint(27, 153.2),
    TankPoint(28, 158.1),
    TankPoint(29, 163.0),
    TankPoint(30, 167.9),
    TankPoint(31, 172.8),
    TankPoint(32, 177.7),
    TankPoint(33, 182.7),
    TankPoint(34, 187.6),
    TankPoint(35, 192.7),
    TankPoint(36, 197.7),
    TankPoint(37, 202.7),
    TankPoint(38, 207.8),
    TankPoint(39, 212.9),
    TankPoint(40, 218.0),
    TankPoint(41, 223.0),
    TankPoint(42, 228.2),
    TankPoint(43, 233.3),
    TankPoint(44, 238.5),
    TankPoint(45, 243.6),
    TankPoint(46, 248.8),
    TankPoint(47, 254.0),
    TankPoint(48, 259.2),
    TankPoint(49, 264.5),
    TankPoint(50, 269.7),
    TankPoint(51, 275.0),
    TankPoint(52, 280.3),
    TankPoint(53, 285.6),
    TankPoint(54, 290.8),
    TankPoint(55, 296.0),
    TankPoint(56, 301.3),
    TankPoint(57, 306.5),
    TankPoint(58, 311.7),
    TankPoint(59, 317.0),
    TankPoint(60, 322.2),
    TankPoint(61, 327.4),
    TankPoint(62, 332.7),
    TankPoint(63, 337.9),
    TankPoint(64, 343.2),
    TankPoint(65, 348.4),
    TankPoint(66, 353.7),
    TankPoint(67, 358.9),
    TankPoint(68, 364.2),
  ],
);

const sandXChart = TankChart(
  id: 'sandx',
  name: 'SandX G3',
  points: [
    TankPoint(1, 4.3),
    TankPoint(2, 8.6),
    TankPoint(3, 12.9),
    TankPoint(4, 17.2),
    TankPoint(5, 21.5),
    TankPoint(6, 25.8),
    TankPoint(7, 30.1),
    TankPoint(8, 34.4),
    TankPoint(9, 38.7),
    TankPoint(10, 43.0),
    TankPoint(11, 47.3),
    TankPoint(12, 51.6),
    TankPoint(13, 55.9),
    TankPoint(14, 60.2),
    TankPoint(15, 64.5),
    TankPoint(16, 68.8),
    TankPoint(17, 73.1),
    TankPoint(18, 77.4),
    TankPoint(19, 81.7),
    TankPoint(20, 86.0),
    TankPoint(21, 90.3),
    TankPoint(22, 94.6),
    TankPoint(23, 98.9),
    TankPoint(24, 103.2),
    TankPoint(25, 107.5),
    TankPoint(26, 111.8),
    TankPoint(27, 116.1),
    TankPoint(28, 120.4),
    TankPoint(29, 124.7),
    TankPoint(30, 129.0),
    TankPoint(31, 133.3),
    TankPoint(32, 137.6),
    TankPoint(33, 141.9),
    TankPoint(34, 146.2),
    TankPoint(35, 150.5),
    TankPoint(36, 154.8),
    TankPoint(37, 159.1),
    TankPoint(38, 163.4),
    TankPoint(39, 168.2),
    TankPoint(40, 173.0),
    TankPoint(41, 177.8),
    TankPoint(42, 182.6),
    TankPoint(43, 187.4),
    TankPoint(44, 192.2),
    TankPoint(45, 197.0),
    TankPoint(46, 201.8),
    TankPoint(47, 206.6),
    TankPoint(48, 211.4),
    TankPoint(49, 216.2),
    TankPoint(50, 220.9),
    TankPoint(51, 225.6),
    TankPoint(52, 230.3),
    TankPoint(53, 235.0),
    TankPoint(54, 239.7),
    TankPoint(55, 244.4),
    TankPoint(56, 249.1),
    TankPoint(57, 253.8),
    TankPoint(58, 258.5),
    TankPoint(59, 263.2),
    TankPoint(60, 267.9),
    TankPoint(61, 272.5),
    TankPoint(62, 277.1),
    TankPoint(63, 281.7),
    TankPoint(64, 286.3),
    TankPoint(65, 290.9),
    TankPoint(66, 295.5),
    TankPoint(67, 300.1),
    TankPoint(68, 304.7),
    TankPoint(69, 309.3),
    TankPoint(70, 313.9),
    TankPoint(71, 318.5),
    TankPoint(72, 323.1),
    TankPoint(73, 327.6),
    TankPoint(74, 332.1),
    TankPoint(75, 336.6),
    TankPoint(76, 341.1),
    TankPoint(77, 345.6),
    TankPoint(78, 350.1),
    TankPoint(79, 354.6),
    TankPoint(80, 359.1),
    TankPoint(81, 363.6),
    TankPoint(82, 368.1),
    TankPoint(83, 372.6),
    TankPoint(84, 377.1),
    TankPoint(85, 381.6),
    TankPoint(86, 386.1),
    TankPoint(87, 390.6),
    TankPoint(88, 395.1),
    TankPoint(89, 399.6),
    TankPoint(90, 404.1),
    TankPoint(91, 408.6),
    TankPoint(92, 413.4),
  ],
);

const flowback500Chart = TankChart(
  id: 'flowback500',
  name: 'Flowback Tank - V Bottom',
  points: [
    TankPoint(3, 3.4),
    TankPoint(6, 9.6),
    TankPoint(9, 17.6),
    TankPoint(12, 27.0),
    TankPoint(15, 37.6),
    TankPoint(18, 49.1),
    TankPoint(21, 61.5),
    TankPoint(24, 74.7),
    TankPoint(27, 88.5),
    TankPoint(30, 103.0),
    TankPoint(33, 117.9),
    TankPoint(36, 133.3),
    TankPoint(39, 149.1),
    TankPoint(42, 165.2),
    TankPoint(45, 181.6),
    TankPoint(48, 198.3),
    TankPoint(51, 215.1),
    TankPoint(54, 232.1),
    TankPoint(57, 249.1),
    TankPoint(60, 266.2),
    TankPoint(63, 283.3),
    TankPoint(66, 300.4),
    TankPoint(69, 317.4),
    TankPoint(72, 334.2),
    TankPoint(75, 350.8),
    TankPoint(78, 367.3),
    TankPoint(81, 383.4),
    TankPoint(84, 399.2),
    TankPoint(87, 414.6),
    TankPoint(90, 429.5),
    TankPoint(93, 443.9),
    TankPoint(96, 457.8),
    TankPoint(99, 470.9),
    TankPoint(102, 483.3),
    TankPoint(105, 494.9),
    TankPoint(108, 505.8),
    TankPoint(111, 514.8),
    TankPoint(114, 522.8),
    TankPoint(117, 529.1),
    TankPoint(120, 532.5),
  ],
);

List<TankPoint> _buildFlowbackRoundBottomWichita500Points() {
  final points = <TankPoint>[];

  // Wichita 500 BBL Round-Bottom Flowback Tank
  points.add(const TankPoint(0, 0));

  for (int inches = 1; inches <= 10; inches++) {
    points.add(TankPoint(inches.toDouble(), inches * 4.5));
  }

  const lowerStartInches = 10.0;
  const lowerStartBarrels = 45.0;
  const lowerEndInches = 44.0;
  const lowerEndBarrels = 200.0;
  const lowerSlope = (lowerEndBarrels - lowerStartBarrels) /
      (lowerEndInches - lowerStartInches);
  for (int inches = 11; inches <= 44; inches++) {
    final barrels =
        lowerStartBarrels + ((inches - lowerStartInches) * lowerSlope);
    points.add(TankPoint(inches.toDouble(), barrels));
  }

  for (int inches = 45; inches <= 104; inches++) {
    points.add(TankPoint(inches.toDouble(), 205.0 + ((inches - 45) * 5.0)));
  }

  return List<TankPoint>.unmodifiable(points);
}

final List<TankPoint> _flowbackRoundBottomWichita500Points =
    _buildFlowbackRoundBottomWichita500Points();

final TankChart flowbackRoundBottomChart = TankChart(
  id: 'flowback_round_bottom',
  name: 'Flowback Tank - Round Bottom',
  points: _flowbackRoundBottomWichita500Points,
);

List<TankPoint> _buildMenardGasTankPoints() {
  const anchors = <int, double>{
    0: 0.00,
    1: 0.53,
    2: 2.12,
    10: 34.48,
    24: 95.10,
    29: 116.75,
    36: 147.06,
    48: 199.02,
    50: 216.66,
    60: 264.76,
    72: 322.48,
    83: 375.39,
    96: 437.92,
    108: 495.64,
    109: 500.45,
    110: 505.26,
  };

  final points = <TankPoint>[];
  for (int inches = 0; inches <= 110; inches++) {
    if (anchors.containsKey(inches)) {
      points.add(TankPoint(inches.toDouble(), anchors[inches]!));
      continue;
    }

    int lower = 0;
    int upper = 110;
    for (final candidate in anchors.keys) {
      if (candidate < inches && candidate >= lower) {
        lower = candidate;
      }
      if (candidate > inches && candidate <= upper) {
        upper = candidate;
      }
    }

    final lowValue = anchors[lower]!;
    final highValue = anchors[upper]!;
    final span = (upper - lower).toDouble();
    final ratio = span == 0 ? 0.0 : (inches - lower) / span;
    final barrels = lowValue + ((highValue - lowValue) * ratio);
    points.add(TankPoint(inches.toDouble(), barrels));
  }
  return List<TankPoint>.unmodifiable(points);
}

final List<TankPoint> _menardGasTankPoints = _buildMenardGasTankPoints();

final TankChart menardGasTankChart = TankChart(
  id: 'menard_gas_tank',
  name: 'Gas Tank - Menard',
  points: _menardGasTankPoints,
);

final TankChart flowbackGasTankChart = menardGasTankChart;
