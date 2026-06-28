import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

class RateCalculatorScreen extends StatefulWidget {
  final String tankName;
  const RateCalculatorScreen({super.key, required this.tankName});

  @override
  State<RateCalculatorScreen> createState() => _RateCalculatorScreenState();
}

class _RateCalculatorScreenState extends State<RateCalculatorScreen> {
  final top = TextEditingController();
  final bottom = TextEditingController();
  final minutes = TextEditingController(text: '60');
  double? result;

  double factorFor(String tank) {
    // TODO: replace FS3/SandX/Flowback with imported chart interpolation from current app.
    if (tank == 'SandX') return .50;
    if (tank == 'Flowback') return 1.67;
    return 1.23;
  }

  double parseGauge(String value) {
    final parts = value.trim().split(' ');
    if (parts.length == 2 && parts[1].contains('/')) {
      final whole = double.tryParse(parts[0]) ?? 0;
      final frac = parts[1].split('/');
      return whole + ((double.tryParse(frac[0]) ?? 0) / (double.tryParse(frac[1]) ?? 1));
    }
    return double.tryParse(value) ?? 0;
  }

  void calculate() {
    final t = parseGauge(top.text);
    final b = parseGauge(bottom.text);
    final m = double.tryParse(minutes.text) ?? 0;
    if (m <= 0) return;
    final barrels = (t - b).abs() * factorFor(widget.tankName);
    setState(() => result = (barrels / m) * 60);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: '${widget.tankName} Rate', showBack: true),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        TextField(controller: top, decoration: const InputDecoration(labelText: 'Top Gauge', hintText: 'Example: 12 3/8')),
        TextField(controller: bottom, decoration: const InputDecoration(labelText: 'Bottom Gauge', hintText: 'Example: 10 1/2')),
        TextField(controller: minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes')),
        const SizedBox(height: 18),
        FilledButton(onPressed: calculate, child: const Text('Calculate')),
        if (result != null) Card(child: Padding(padding: const EdgeInsets.all(18), child: Text('${result!.toStringAsFixed(1)} BBL/hr', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)))),
        OutlinedButton(onPressed: () {}, child: const Text('Save Reading')),
      ]),
    );
  }
}
