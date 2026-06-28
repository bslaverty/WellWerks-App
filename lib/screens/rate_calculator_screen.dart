import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class RateCalculatorScreen extends StatefulWidget {
  final String tankName;
  const RateCalculatorScreen({super.key, required this.tankName});

  @override
  State<RateCalculatorScreen> createState() => _RateCalculatorScreenState();
}

class _RateCalculatorScreenState extends State<RateCalculatorScreen> {
  final top = TextEditingController();
  final bottom = TextEditingController();
  final minutes = TextEditingController();
  double? result;
  String? error;

  double factorFor(String tank) {
    // Temporary until the real FS3/SandX/Flowback chart data is migrated.
    if (tank == 'SandX') return .50;
    if (tank == 'Flowback') return 1.67;
    return 1.23;
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

  void clearInputs() {
    setState(() {
      top.clear();
      bottom.clear();
      minutes.clear();
      result = null;
      error = null;
    });
  }

  void calculate() {
    final m = double.tryParse(minutes.text) ?? 0;
    if (top.text.trim().isEmpty || bottom.text.trim().isEmpty || minutes.text.trim().isEmpty) {
      setState(() {
        result = null;
        error = 'Enter top gauge, bottom gauge, and minutes.';
      });
      return;
    }
    if (m <= 0) {
      setState(() {
        result = null;
        error = 'Minutes must be greater than zero.';
      });
      return;
    }
    final t = parseGauge(top.text);
    final b = parseGauge(bottom.text);
    final barrels = (t - b).abs() * factorFor(widget.tankName);
    setState(() {
      result = (barrels / m) * 60;
      error = null;
    });
  }

  @override
  void dispose() {
    top.dispose();
    bottom.dispose();
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: '${widget.tankName} Rate', showBack: true),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text(
          'Fields start blank so no old or sample numbers get mixed into your calculation.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 14),
        WwGaugeField(label: 'Top Gauge', controller: top, autofocus: true),
        WwGaugeField(label: 'Bottom Gauge', controller: bottom),
        WwNumberField(label: 'Minutes', controller: minutes, allowDecimal: true, textInputAction: TextInputAction.done),
        const SizedBox(height: 4),
        FilledButton(onPressed: calculate, child: const Text('Calculate')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: clearInputs, icon: const Icon(Icons.clear), child: const Text('Clear')), 
        if (error != null)
          Card(
            color: const Color(0xFF3A1E1E),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(error!, style: const TextStyle(color: Colors.white)),
            ),
          ),
        if (result != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                '${result!.toStringAsFixed(1)} BBL/hr',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        OutlinedButton(onPressed: () {}, child: const Text('Save Reading')),
      ]),
    );
  }
}
