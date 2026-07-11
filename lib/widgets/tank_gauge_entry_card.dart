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
                  child: TextField(
                    controller: fractionOrDecimalController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Fraction or Decimal',
                      hintText: '1/2 or .5',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Gauge: ${gauge.toStringAsFixed(2)}"   •   Barrels: ${barrels.toStringAsFixed(2)} bbl',
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
