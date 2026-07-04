import 'package:flutter/material.dart';
import '../data/tank_charts.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class RateCalculatorConfig {
  final String title;
  final String? chartId;
  final double? defaultFactor;

  const RateCalculatorConfig.chart(this.title, this.chartId) : defaultFactor = null;
  const RateCalculatorConfig.linear(this.title, {required this.defaultFactor}) : chartId = null;

  bool get usesChart => chartId != null;
}

class RateCalculatorScreen extends StatefulWidget {
  final RateCalculatorConfig config;
  const RateCalculatorScreen({super.key, required this.config});

  // Backward compatibility for old routes still passing a tank name.
  factory RateCalculatorScreen.legacy({Key? key, required String tankName}) {
    switch (tankName) {
      case 'SandX':
        return RateCalculatorScreen(key: key, config: const RateCalculatorConfig.chart('SandX G3', 'sandx'));
      case 'Flowback':
        return RateCalculatorScreen(key: key, config: const RateCalculatorConfig.chart('500 BBL Flowback Tank', 'flowback500'));
      case 'Production Tank':
        return RateCalculatorScreen(key: key, config: const RateCalculatorConfig.linear('Production Tank', defaultFactor: 1.67));
      case 'FS3':
      default:
        return RateCalculatorScreen(key: key, config: const RateCalculatorConfig.chart('FS3 Tank', 'fs3'));
    }
  }

  @override
  State<RateCalculatorScreen> createState() => _RateCalculatorScreenState();
}

class _RateCalculatorScreenState extends State<RateCalculatorScreen> {
  final startGauge = TextEditingController();
  final endGauge = TextEditingController();
  final minutes = TextEditingController();
  late final TextEditingController factor;

  double? bblPerMin;
  double? bblPerHr;
  double? bblPerDay;
  String? error;

  @override
  void initState() {
    super.initState();
    factor = TextEditingController(text: (widget.config.defaultFactor ?? 1.67).toString());
  }

  TankChart? get chart {
    switch (widget.config.chartId) {
      case 'fs3':
        return fs3Chart;
      case 'sandx':
        return sandXChart;
      case 'flowback500':
        return flowback500Chart;
    }
    return null;
  }

  double parseGauge(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 0;
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 2 && parts[1].contains('/')) {
      final whole = double.tryParse(parts[0]) ?? 0;
      final frac = parts[1].split('/');
      final numerator = double.tryParse(frac.first) ?? 0;
      final denominator = frac.length > 1 ? (double.tryParse(frac[1]) ?? 1) : 1;
      return whole + (numerator / denominator);
    }
    if (clean.contains('/')) {
      final frac = clean.split('/');
      final numerator = double.tryParse(frac.first) ?? 0;
      final denominator = frac.length > 1 ? (double.tryParse(frac[1]) ?? 1) : 1;
      return numerator / denominator;
    }
    return double.tryParse(clean) ?? 0;
  }

  double barrelsAt(double inches) {
    final c = chart;
    if (c != null) return c.barrelsAt(inches);
    final f = double.tryParse(factor.text.trim()) ?? 1.67;
    return inches * f;
  }

  void clearInputs() {
    setState(() {
      startGauge.clear();
      endGauge.clear();
      minutes.clear();
      bblPerMin = null;
      bblPerHr = null;
      bblPerDay = null;
      error = null;
    });
  }

  void calculate() {
    final m = double.tryParse(minutes.text.trim()) ?? 0;
    if (startGauge.text.trim().isEmpty || endGauge.text.trim().isEmpty || minutes.text.trim().isEmpty) {
      setState(() => error = 'Enter start gauge, end gauge, and minutes.');
      return;
    }
    if (m <= 0) {
      setState(() => error = 'Minutes must be greater than zero.');
      return;
    }
    if (!widget.config.usesChart && (double.tryParse(factor.text.trim()) ?? 0) <= 0) {
      setState(() => error = 'Tank factor must be greater than zero.');
      return;
    }

    final startBbl = barrelsAt(parseGauge(startGauge.text));
    final endBbl = barrelsAt(parseGauge(endGauge.text));
    final change = (endBbl - startBbl).abs();
    final perMin = change / m;

    setState(() {
      bblPerMin = perMin;
      bblPerHr = perMin * 60;
      bblPerDay = perMin * 1440;
      error = null;
    });
  }

  @override
  void dispose() {
    startGauge.dispose();
    endGauge.dispose();
    minutes.dispose();
    factor.dispose();
    super.dispose();
  }

  Widget _resultCard(String label, String value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppHeader(title: widget.config.title, showBack: true),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (widget.config.usesChart)
              Text('Using ${chart?.name ?? 'tank'} strapping chart with interpolation.', style: const TextStyle(color: Colors.white70))
            else
              WwNumberField(label: 'Tank Factor (BBL/In)', controller: factor, allowDecimal: true),
            const SizedBox(height: 12),
            WwGaugeField(label: 'Start Gauge', controller: startGauge, autofocus: true),
            WwGaugeField(label: 'End Gauge', controller: endGauge),
            WwNumberField(label: 'Minutes', controller: minutes, allowDecimal: true, textInputAction: TextInputAction.done),
            const SizedBox(height: 4),
            FilledButton(onPressed: calculate, child: const Text('Calculate')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: clearInputs, icon: const Icon(Icons.clear), label: const Text('Clear')),
            if (error != null)
              Card(
                color: const Color(0xFF3A1E1E),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(error!, style: const TextStyle(color: Colors.white)),
                ),
              ),
            if (bblPerMin != null) ...[
              const SizedBox(height: 10),
              _resultCard('BBL/min', bblPerMin!.toStringAsFixed(3)),
              _resultCard('BBL/hr', bblPerHr!.toStringAsFixed(1)),
              _resultCard('BBL/day', bblPerDay!.toStringAsFixed(1)),
            ],
          ],
        ),
      );
}
