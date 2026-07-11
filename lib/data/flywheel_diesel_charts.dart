import 'dart:math' as math;

class DieselChartPoint {
  const DieselChartPoint({required this.inches, required this.gallons});

  final double inches;
  final double gallons;
}

class DieselCompartmentChart {
  const DieselCompartmentChart({
    required this.id,
    required this.name,
    required this.nominalGallons,
    required this.shellFullGallons,
    required this.points,
  });

  final String id;
  final String name;
  final int nominalGallons;
  final int shellFullGallons;
  final List<DieselChartPoint> points;

  double gallonsAt(double inches) {
    if (points.isEmpty) return 0;
    final clamped = inches.clamp(points.first.inches, points.last.inches);
    if (clamped <= points.first.inches) return points.first.gallons;
    if (clamped >= points.last.inches) return points.last.gallons;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (clamped >= a.inches && clamped <= b.inches) {
        final span = b.inches - a.inches;
        if (span == 0) return a.gallons;
        final percent = (clamped - a.inches) / span;
        return a.gallons + ((b.gallons - a.gallons) * percent);
      }
    }
    return 0;
  }
}

class FlywheelDieselCharts {
  static const _maxInches = 120.0;

  // Compartment charts are kept independent so each section uses its own lookup.
  static final DieselCompartmentChart compartment1 = _buildCompartmentChart(
    id: 'flywheel_compartment_1',
    name: 'Compartment 1',
    nominalGallons: 3500,
    shellFullGallons: 3756,
    exponent: 0.3917,
  );

  static final DieselCompartmentChart compartment2 = _buildCompartmentChart(
    id: 'flywheel_compartment_2',
    name: 'Compartment 2',
    nominalGallons: 1300,
    shellFullGallons: 1404,
    exponent: 0.3917,
  );

  static final DieselCompartmentChart compartment3 = _buildCompartmentChart(
    id: 'flywheel_compartment_3',
    name: 'Compartment 3',
    nominalGallons: 2000,
    shellFullGallons: 2282,
    exponent: 0.8290,
  );

  static DieselCompartmentChart _buildCompartmentChart({
    required String id,
    required String name,
    required int nominalGallons,
    required int shellFullGallons,
    required double exponent,
  }) {
    final points = <DieselChartPoint>[];
    for (var i = 0; i <= (_maxInches * 4).round(); i++) {
      final inches = i / 4.0;
      final ratio = (inches / _maxInches).clamp(0.0, 1.0);
      final gallons = shellFullGallons * math.pow(ratio, exponent).toDouble();
      points.add(DieselChartPoint(
        inches: inches,
        gallons: (gallons * 10).roundToDouble() / 10,
      ));
    }

    return DieselCompartmentChart(
      id: id,
      name: name,
      nominalGallons: nominalGallons,
      shellFullGallons: shellFullGallons,
      points: points,
    );
  }
}
