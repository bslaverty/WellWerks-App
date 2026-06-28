import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class ProductionTankScreen extends StatefulWidget {
  const ProductionTankScreen({super.key});
  @override
  State<ProductionTankScreen> createState() => _ProductionTankScreenState();
}

class _ProductionTankScreenState extends State<ProductionTankScreen> {
  final factor = TextEditingController(text: '1.67');
  final top = TextEditingController();
  final bottom = TextEditingController();
  final hours = TextEditingController();
  double? bbl;
  double? rate;
  String? error;

  void clearInputs() {
    setState(() {
      top.clear();
      bottom.clear();
      hours.clear();
      bbl = null;
      rate = null;
      error = null;
    });
  }

  void calculate() {
    final f = double.tryParse(factor.text) ?? 1.67;
    final t = double.tryParse(top.text) ?? 0;
    final b = double.tryParse(bottom.text) ?? 0;
    final h = double.tryParse(hours.text) ?? 0;
    if (top.text.trim().isEmpty || bottom.text.trim().isEmpty || hours.text.trim().isEmpty) {
      setState(() {
        bbl = null;
        rate = null;
        error = 'Enter top gauge, bottom gauge, and hours.';
      });
      return;
    }
    if (h <= 0) {
      setState(() {
        bbl = null;
        rate = null;
        error = 'Hours must be greater than zero.';
      });
      return;
    }
    final produced = (t - b).abs() * f;
    setState(() {
      bbl = produced;
      rate = produced / h;
      error = null;
    });
  }

  @override
  void dispose() {
    factor.dispose();
    top.dispose();
    bottom.dispose();
    hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppHeader(title: 'Production Tank', showBack: true),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          WwNumberField(
            controller: factor,
            label: 'Tank Factor (BBL/In)',
            helperText: 'Use the actual tank factor. Default: 1.67',
          ),
          WwNumberField(label: 'Top Gauge', controller: top, autofocus: true),
          WwNumberField(label: 'Bottom Gauge', controller: bottom),
          WwNumberField(label: 'Hours', controller: hours, textInputAction: TextInputAction.done),
          const SizedBox(height: 4),
          FilledButton(onPressed: calculate, child: const Text('Calculate')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: clearInputs, icon: const Icon(Icons.clear), child: const Text('Clear Gauges')), 
          if (error != null)
            Card(
              color: const Color(0xFF3A1E1E),
              child: Padding(padding: const EdgeInsets.all(14), child: Text(error!)),
            ),
          if (bbl != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  '${bbl!.toStringAsFixed(1)} BBL\n${rate!.toStringAsFixed(1)} BBL/hr',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ]),
      );
}
