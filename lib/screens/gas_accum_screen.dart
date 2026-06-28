import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class GasAccumScreen extends StatefulWidget {
  const GasAccumScreen({super.key});
  @override
  State<GasAccumScreen> createState() => _GasAccumScreenState();
}

class _GasAccumScreenState extends State<GasAccumScreen> {
  final previous = TextEditingController();
  final current = TextEditingController();
  final hours = TextEditingController();
  double? rate;
  String? error;

  void clearInputs() {
    setState(() {
      previous.clear();
      current.clear();
      hours.clear();
      rate = null;
      error = null;
    });
  }

  void calculate() {
    final p = double.tryParse(previous.text) ?? 0;
    final c = double.tryParse(current.text) ?? 0;
    final h = double.tryParse(hours.text) ?? 0;
    if (previous.text.trim().isEmpty || current.text.trim().isEmpty || hours.text.trim().isEmpty) {
      setState(() {
        rate = null;
        error = 'Enter previous reading, current reading, and hours.';
      });
      return;
    }
    if (h <= 0) {
      setState(() {
        rate = null;
        error = 'Hours must be greater than zero.';
      });
      return;
    }
    setState(() {
      rate = ((c - p).abs() / h) * 24;
      error = null;
    });
  }

  @override
  void dispose() {
    previous.dispose();
    current.dispose();
    hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppHeader(title: 'Gas Accum', showBack: true),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          WwNumberField(label: 'Previous Reading', controller: previous, autofocus: true),
          WwNumberField(label: 'Current Reading', controller: current),
          WwNumberField(label: 'Hours', controller: hours, textInputAction: TextInputAction.done),
          const SizedBox(height: 4),
          FilledButton(onPressed: calculate, child: const Text('Calculate')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: clearInputs, icon: const Icon(Icons.clear), child: const Text('Clear')), 
          if (error != null)
            Card(color: const Color(0xFF3A1E1E), child: Padding(padding: const EdgeInsets.all(14), child: Text(error!))),
          if (rate != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text('${rate!.toStringAsFixed(0)} MCFD', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              ),
            ),
        ]),
      );
}
