import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

class GasAccumScreen extends StatefulWidget {
  const GasAccumScreen({super.key});
  @override
  State<GasAccumScreen> createState() => _GasAccumScreenState();
}

class _GasAccumScreenState extends State<GasAccumScreen> {
  final previous = TextEditingController();
  final current = TextEditingController();
  final hours = TextEditingController(text: '1');
  double? rate;

  void calculate() {
    final p = double.tryParse(previous.text) ?? 0;
    final c = double.tryParse(current.text) ?? 0;
    final h = double.tryParse(hours.text) ?? 0;
    if (h <= 0) return;
    setState(() => rate = ((c - p).abs() / h) * 24);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppHeader(title: 'Gas Accum', showBack: true),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      TextField(controller: previous, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Previous Reading')),
      TextField(controller: current, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current Reading')),
      TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hours')),
      const SizedBox(height: 18),
      FilledButton(onPressed: calculate, child: const Text('Calculate')),
      if (rate != null) Card(child: Padding(padding: const EdgeInsets.all(18), child: Text('${rate!.toStringAsFixed(0)} MCFD', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)))),
    ]),
  );
}
