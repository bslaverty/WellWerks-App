import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

class ProductionTankScreen extends StatefulWidget {
  const ProductionTankScreen({super.key});
  @override
  State<ProductionTankScreen> createState() => _ProductionTankScreenState();
}

class _ProductionTankScreenState extends State<ProductionTankScreen> {
  final factor = TextEditingController(text: '1.67');
  final top = TextEditingController();
  final bottom = TextEditingController();
  final hours = TextEditingController(text: '1');
  double? bbl;
  double? rate;

  void calculate() {
    final f = double.tryParse(factor.text) ?? 1.67;
    final t = double.tryParse(top.text) ?? 0;
    final b = double.tryParse(bottom.text) ?? 0;
    final h = double.tryParse(hours.text) ?? 0;
    if (h <= 0) return;
    final produced = (t - b).abs() * f;
    setState(() { bbl = produced; rate = produced / h; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppHeader(title: 'Production Tank', showBack: true),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      TextField(controller: factor, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tank Factor (BBL/In)', helperText: 'Use the actual tank factor. Default: 1.67')),
      TextField(controller: top, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Top Gauge')),
      TextField(controller: bottom, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bottom Gauge')),
      TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hours')),
      const SizedBox(height: 18),
      FilledButton(onPressed: calculate, child: const Text('Calculate')),
      if (bbl != null) Card(child: Padding(padding: const EdgeInsets.all(18), child: Text('${bbl!.toStringAsFixed(1)} BBL\n${rate!.toStringAsFixed(1)} BBL/hr', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)))),
    ]),
  );
}
