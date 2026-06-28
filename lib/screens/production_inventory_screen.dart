import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class ProductionInventoryScreen extends StatefulWidget {
  const ProductionInventoryScreen({super.key});
  @override
  State<ProductionInventoryScreen> createState() => _ProductionInventoryScreenState();
}

class _ProductionInventoryScreenState extends State<ProductionInventoryScreen> {
  final oilProduced = TextEditingController();
  final oilHauled = TextEditingController();
  final oilPumped = TextEditingController();
  final oilCapacity = TextEditingController();
  final waterProduced = TextEditingController();
  final waterHauled = TextEditingController();
  final waterPumped = TextEditingController();
  final waterCapacity = TextEditingController();

  double n(TextEditingController c) => double.tryParse(c.text) ?? 0;

  String status(double pct) {
    if (pct >= 95) return '🔴 Full';
    if (pct >= 90) return '🟠 High';
    if (pct >= 75) return '🟡 Near Full';
    return '🟢 Normal';
  }

  Color statusColor(double pct) {
    if (pct >= 95) return const Color(0xFFFF5C5C);
    if (pct >= 90) return const Color(0xFFFF9B3D);
    if (pct >= 75) return const Color(0xFFFFD45D);
    return const Color(0xFF55D980);
  }

  @override
  void dispose() {
    for (final c in [oilProduced, oilHauled, oilPumped, oilCapacity, waterProduced, waterHauled, waterPumped, waterCapacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget inventoryCard({required String title, required double onLocation, required double capacity}) {
    final pct = capacity <= 0 ? 0.0 : (onLocation / capacity * 100).clamp(0, 999).toDouble();
    final color = statusColor(pct);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('${onLocation.toStringAsFixed(1)} BBL on location', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          if (capacity > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 14, color: color, backgroundColor: const Color(0xFF111111)),
            ),
            const SizedBox(height: 8),
            Text('${pct.toStringAsFixed(0)}% • ${status(pct)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
          if (onLocation < 0)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('⚠ Inventory is negative. Check produced, hauled, or pumped entries.', style: TextStyle(color: Color(0xFFFFD45D), fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oil = n(oilProduced) - n(oilHauled) - n(oilPumped);
    final water = n(waterProduced) - n(waterHauled) - n(waterPumped);
    return Scaffold(
      appBar: const AppHeader(title: 'Production Inventory', showBack: true),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Oil', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 22, fontWeight: FontWeight.bold)),
        WwNumberField(label: 'Oil Produced', controller: oilProduced),
        WwNumberField(label: 'Oil Hauled', controller: oilHauled),
        WwNumberField(label: 'Oil Pumped', controller: oilPumped),
        WwNumberField(label: 'Oil Tank Capacity', controller: oilCapacity, helperText: 'Optional. Alerts start at 75%.'),
        inventoryCard(title: 'Oil', onLocation: oil, capacity: n(oilCapacity)),
        const SizedBox(height: 14),
        const Text('Water', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 22, fontWeight: FontWeight.bold)),
        WwNumberField(label: 'Water Produced', controller: waterProduced),
        WwNumberField(label: 'Water Hauled', controller: waterHauled),
        WwNumberField(label: 'Water Pumped', controller: waterPumped),
        WwNumberField(label: 'Water Tank Capacity', controller: waterCapacity, helperText: 'Optional. Alerts start at 75%.'),
        inventoryCard(title: 'Water', onLocation: water, capacity: n(waterCapacity)),
        const Text('Alert defaults: 🟢 <75%  🟡 75%  🟠 90%  🔴 95%', style: TextStyle(color: Colors.white70)),
      ]),
    );
  }
}
