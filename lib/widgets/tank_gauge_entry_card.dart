import 'package:flutter/material.dart';

import '../data/tank_charts.dart';

class TankGaugeEntryCard extends StatelessWidget {
  const TankGaugeEntryCard({
    super.key,
    required this.title,
    required this.chart,
    required this.wholeInchesController,
    required this.fractionOrDecimalController,
    required this.onChanged,
    this.showDivider = true,
  });

  final String title;
  final TankChart chart;
  final TextEditingController wholeInchesController;
  final TextEditingController fractionOrDecimalController;
  final VoidCallback onChanged;
  final bool showDivider;

  static const List<double> _fractionSteps = [
    0,
    1 / 8,
    1 / 4,
    3 / 8,
    1 / 2,
    5 / 8,
    3 / 4,
    7 / 8,
  ];

  double _parseGauge() {
    final whole = double.tryParse(wholeInchesController.text.trim()) ?? 0;
    final fractionRaw = fractionOrDecimalController.text.trim();
    if (fractionRaw.isEmpty) return whole;

    if (fractionRaw.contains('/')) {
      final parts = fractionRaw.split('/');
      if (parts.length == 2) {
        final top = double.tryParse(parts.first.trim()) ?? 0;
        final bottom = double.tryParse(parts.last.trim()) ?? 1;
        if (bottom != 0) {
          return whole + (top / bottom);
        }
      }
    }

    final decimal = double.tryParse(fractionRaw) ?? 0;
    return whole + decimal;
  }

  String _fmtTrim(double value) {
    if (value.isNaN || value.isInfinite) return '--';
    final s = value.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.00$'), '').replaceFirst(RegExp(r'0$'), '');
  }

  double _selectedFractionValue() {
    final raw = fractionOrDecimalController.text.trim();
    if (raw.isEmpty) return 0;
    var value = 0.0;
    if (raw.contains('/')) {
      final parts = raw.split('/');
      if (parts.length == 2) {
        final top = double.tryParse(parts[0].trim()) ?? 0;
        final bottom = double.tryParse(parts[1].trim()) ?? 1;
        value = bottom == 0 ? 0 : top / bottom;
      }
    } else {
      value = double.tryParse(raw) ?? 0;
    }
    for (final step in _fractionSteps) {
      if ((value - step).abs() < 0.001) return step;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gauge = _parseGauge();
    final barrels = chart.barrelsAt(gauge);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: wholeInchesController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Whole Inches',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<double>(
                    initialValue: _selectedFractionValue(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('0')),
                      DropdownMenuItem(value: 1 / 8, child: Text('1/8')),
                      DropdownMenuItem(value: 1 / 4, child: Text('1/4')),
                      DropdownMenuItem(value: 3 / 8, child: Text('3/8')),
                      DropdownMenuItem(value: 1 / 2, child: Text('1/2')),
                      DropdownMenuItem(value: 5 / 8, child: Text('5/8')),
                      DropdownMenuItem(value: 3 / 4, child: Text('3/4')),
                      DropdownMenuItem(value: 7 / 8, child: Text('7/8')),
                    ],
                    onChanged: (value) {
                      final next = (value ?? 0).toString();
                      fractionOrDecimalController.text = next;
                      onChanged();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Fraction',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Gauge: ${_fmtTrim(gauge)}"   •   Barrels: ${_fmtTrim(barrels)} bbl',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Divider(color: scheme.primary.withValues(alpha: 0.3)),
              ),
          ],
        ),
      ),
    );
  }
}
