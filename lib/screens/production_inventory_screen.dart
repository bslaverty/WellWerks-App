import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

class ProductionInventoryScreen extends StatefulWidget { const ProductionInventoryScreen({super.key}); @override State<ProductionInventoryScreen> createState() => _ProductionInventoryScreenState(); }
class _ProductionInventoryScreenState extends State<ProductionInventoryScreen> {
  final oilProduced = TextEditingController(); final oilHauled = TextEditingController(); final oilPumped = TextEditingController();
  final waterProduced = TextEditingController(); final waterHauled = TextEditingController(); final waterPumped = TextEditingController();
  double n(TextEditingController c)=>double.tryParse(c.text)??0;
  String status(double pct){ if(pct>=95)return '🔴 Full'; if(pct>=90)return '🟠 High'; if(pct>=75)return '🟡 Near Full'; return '🟢 Normal'; }
  @override Widget build(BuildContext context){
    final oil = n(oilProduced)-n(oilHauled)-n(oilPumped); final water=n(waterProduced)-n(waterHauled)-n(waterPumped);
    return Scaffold(appBar: const AppHeader(title:'Production Inventory',showBack:true), body: ListView(padding: const EdgeInsets.all(18), children:[
      const Text('Oil', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 22, fontWeight: FontWeight.bold)),
      TextField(controller: oilProduced, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Oil Produced')),
      TextField(controller: oilHauled, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Oil Hauled')),
      TextField(controller: oilPumped, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Oil Pumped')),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Oil On Location: ${oil.toStringAsFixed(1)} BBL'))),
      const Text('Water', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 22, fontWeight: FontWeight.bold)),
      TextField(controller: waterProduced, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Water Produced')),
      TextField(controller: waterHauled, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Water Hauled')),
      TextField(controller: waterPumped, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Water Pumped')),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Water On Location: ${water.toStringAsFixed(1)} BBL'))),
      const Text('Alert defaults: 🟢 <75%  🟡 75%  🟠 90%  🔴 95%', style: TextStyle(color: Colors.white70)),
    ]));
  }
}
