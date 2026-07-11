import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/flywheel_diesel_charts.dart';
import '../services/app_settings_service.dart';
import '../widgets/app_header.dart';

class FlywheelDieselTankScreen extends StatefulWidget {
  const FlywheelDieselTankScreen({super.key});

  @override
  State<FlywheelDieselTankScreen> createState() =>
      _FlywheelDieselTankScreenState();
}

class _FlywheelDieselTankScreenState extends State<FlywheelDieselTankScreen> {
  final _settingsService = AppSettingsService();

  String _timeFormat = '12h';

  int? _comp1Feet;
  int? _comp1Inches;
  double _comp1Quarter = 0;

  int? _comp2Feet;
  int? _comp2Inches;
  double _comp2Quarter = 0;

  int? _comp3Feet;
  int? _comp3Inches;
  double _comp3Quarter = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      _timeFormat = settings.textTimeFormat;
    });
  }

  double? _toInches(int? feet, int? inches, double quarter) {
    if (feet == null || inches == null) return null;
    return (feet * 12) + inches + quarter;
  }

  int _gallons(
      DieselCompartmentChart chart, int? feet, int? inches, double quarter) {
    final totalInches = _toInches(feet, inches, quarter);
    if (totalInches == null) return 0;
    return chart.gallonsAt(totalInches).round();
  }

  int get _comp1Gallons => _gallons(
        FlywheelDieselCharts.compartment1,
        _comp1Feet,
        _comp1Inches,
        _comp1Quarter,
      );

  int get _comp2Gallons => _gallons(
        FlywheelDieselCharts.compartment2,
        _comp2Feet,
        _comp2Inches,
        _comp2Quarter,
      );

  int get _comp3Gallons => _gallons(
        FlywheelDieselCharts.compartment3,
        _comp3Feet,
        _comp3Inches,
        _comp3Quarter,
      );

  int get _totalGallons => _comp1Gallons + _comp2Gallons + _comp3Gallons;

  String _fmtInt(int value) {
    return NumberFormat('#,##0').format(value);
  }

  String _timeLine() {
    final now = DateTime.now();
    if (_timeFormat == '24h') {
      return DateFormat('HH:mm').format(now);
    }
    return DateFormat('h:mm a').format(now);
  }

  String _copyText() {
    final lines = <String>[
      'Flywheel',
      'Diesel Tank Totals',
      _timeLine(),
      '',
      'Compartment 1: ${_fmtInt(_comp1Gallons)} gal',
      'Compartment 2: ${_fmtInt(_comp2Gallons)} gal',
      'Compartment 3: ${_fmtInt(_comp3Gallons)} gal',
      '',
      'Total Diesel: ${_fmtInt(_totalGallons)} gal',
    ];
    return lines.join('\n');
  }

  Future<void> _copyDieselTotals() async {
    await Clipboard.setData(ClipboardData(text: _copyText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diesel totals copied to clipboard.')),
    );
  }

  Future<void> _clearReadings() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Diesel Readings?'),
            content: const Text(
              'This clears compartment gauges and calculated diesel totals for this screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Readings'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _comp1Feet = null;
      _comp1Inches = null;
      _comp1Quarter = 0;
      _comp2Feet = null;
      _comp2Inches = null;
      _comp2Quarter = 0;
      _comp3Feet = null;
      _comp3Inches = null;
      _comp3Quarter = 0;
    });
  }

  Widget _gaugeCard({
    required String title,
    required int nominalGallons,
    required int shellFullGallons,
    required int? feet,
    required int? inches,
    required double quarter,
    required ValueChanged<int?> onFeetChanged,
    required ValueChanged<int?> onInchesChanged,
    required ValueChanged<double?> onQuarterChanged,
    required int gallons,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nominal: ${_fmtInt(nominalGallons)} gal   •   Shell Full: ${_fmtInt(shellFullGallons)} gal',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: feet,
                    decoration: const InputDecoration(
                      labelText: 'Feet',
                    ),
                    items: List.generate(
                      11,
                      (i) => DropdownMenuItem<int>(
                        value: i,
                        child: Text('$i ft'),
                      ),
                    ),
                    onChanged: onFeetChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: inches,
                    decoration: const InputDecoration(
                      labelText: 'Inches',
                    ),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem<int>(
                        value: i,
                        child: Text('$i in'),
                      ),
                    ),
                    onChanged: onInchesChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<double>(
                    initialValue: quarter,
                    decoration: const InputDecoration(
                      labelText: 'Quarter',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('0')),
                      DropdownMenuItem(value: 0.25, child: Text('1/4')),
                      DropdownMenuItem(value: 0.5, child: Text('1/2')),
                      DropdownMenuItem(value: 0.75, child: Text('3/4')),
                    ],
                    onChanged: onQuarterChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Gallons: ${_fmtInt(gallons)} gal',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AppHeader(title: 'Flywheel Diesel Tank', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Flywheel',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Diesel Tank Totals',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeLine(),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Total Diesel: ${_fmtInt(_totalGallons)} gal',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _gaugeCard(
            title: 'Compartment 1',
            nominalGallons: FlywheelDieselCharts.compartment1.nominalGallons,
            shellFullGallons:
                FlywheelDieselCharts.compartment1.shellFullGallons,
            feet: _comp1Feet,
            inches: _comp1Inches,
            quarter: _comp1Quarter,
            gallons: _comp1Gallons,
            onFeetChanged: (value) => setState(() => _comp1Feet = value),
            onInchesChanged: (value) => setState(() => _comp1Inches = value),
            onQuarterChanged: (value) =>
                setState(() => _comp1Quarter = value ?? 0),
          ),
          _gaugeCard(
            title: 'Compartment 2',
            nominalGallons: FlywheelDieselCharts.compartment2.nominalGallons,
            shellFullGallons:
                FlywheelDieselCharts.compartment2.shellFullGallons,
            feet: _comp2Feet,
            inches: _comp2Inches,
            quarter: _comp2Quarter,
            gallons: _comp2Gallons,
            onFeetChanged: (value) => setState(() => _comp2Feet = value),
            onInchesChanged: (value) => setState(() => _comp2Inches = value),
            onQuarterChanged: (value) =>
                setState(() => _comp2Quarter = value ?? 0),
          ),
          _gaugeCard(
            title: 'Compartment 3',
            nominalGallons: FlywheelDieselCharts.compartment3.nominalGallons,
            shellFullGallons:
                FlywheelDieselCharts.compartment3.shellFullGallons,
            feet: _comp3Feet,
            inches: _comp3Inches,
            quarter: _comp3Quarter,
            gallons: _comp3Gallons,
            onFeetChanged: (value) => setState(() => _comp3Feet = value),
            onInchesChanged: (value) => setState(() => _comp3Inches = value),
            onQuarterChanged: (value) =>
                setState(() => _comp3Quarter = value ?? 0),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _copyDieselTotals,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Diesel Totals'),
              ),
              OutlinedButton.icon(
                onPressed: _clearReadings,
                icon: const Icon(Icons.clear),
                label: const Text('Clear Readings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
