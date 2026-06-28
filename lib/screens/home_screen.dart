import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import '../widgets/section_title.dart';
import 'rate_calculator_screen.dart';
import 'gas_accum_screen.dart';
import 'production_tank_screen.dart';
import 'production_inventory_screen.dart';
import 'equipment_screen.dart';
import 'jsa_screen.dart';
import 'active_shift_screen.dart';
import 'pressure_entry_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(showBack: false),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionTitle('Favorites'),
          Wrap(spacing: 10, runSpacing: 10, children: const [
            Chip(label: Text('FS3 Rate')),
            Chip(label: Text('Gas Accum')),
            Chip(label: Text('Shift Report')),
            Chip(label: Text('Sand Chart')),
          ]),
          const SectionTitle('⚡ Shift'),
          ToolCard(icon: Icons.dashboard_customize, title: 'Active Shift', subtitle: 'Current readings, pressure entry, and round history', onTap: () => open(context, const ActiveShiftScreen())),
          ToolCard(icon: Icons.add_circle, title: 'Quick Round', subtitle: 'Enter production and pressure readings once', onTap: () => open(context, const PressureEntryScreen())),
          const SectionTitle('🌊 Flowback'),
          ToolCard(icon: Icons.speed, title: 'FS3 Rate', subtitle: 'Use FS3 tank chart', onTap: () => open(context, const RateCalculatorScreen(tankName: 'FS3'))),
          ToolCard(icon: Icons.speed, title: 'SandX Rate', subtitle: 'Use SandX tank chart', onTap: () => open(context, const RateCalculatorScreen(tankName: 'SandX'))),
          ToolCard(icon: Icons.speed, title: 'Flowback Tank Rate', subtitle: 'Use Flowback tank chart', onTap: () => open(context, const RateCalculatorScreen(tankName: 'Flowback'))),
          ToolCard(icon: Icons.arrow_downward, title: 'Bottoms Up', subtitle: 'Pipe volume and lag time', onTap: () {}),
          ToolCard(icon: Icons.tune, title: 'Multiple Choke', subtitle: 'Equivalent choke size', onTap: () {}),
          ToolCard(icon: Icons.water_drop, title: 'Chlorides', subtitle: 'Chloride calculations', onTap: () {}),
          const SectionTitle('🛢 Production'),
          ToolCard(icon: Icons.local_fire_department, title: 'Gas Accum', subtitle: 'Hourly gas accumulation', onTap: () => open(context, const GasAccumScreen())),
          ToolCard(icon: Icons.oil_barrel, title: 'Production Tank', subtitle: 'Editable Tank Factor, default 1.67', onTap: () => open(context, const ProductionTankScreen())),
          ToolCard(icon: Icons.inventory, title: 'Production Inventory', subtitle: 'Produced, hauled, pumped, on location', onTap: () => open(context, const ProductionInventoryScreen())),
          const SectionTitle('📚 Charts'),
          ToolCard(icon: Icons.grid_on, title: 'Sand Chart', subtitle: 'Reference chart', onTap: () {}),
          ToolCard(icon: Icons.settings_input_component, title: 'Flange Chart', subtitle: 'Reference chart', onTap: () {}),
          ToolCard(icon: Icons.table_chart, title: 'Tank Charts', subtitle: 'FS3, SandX, Flowback', onTap: () {}),
          const SectionTitle('📋 Reports'),
          ToolCard(icon: Icons.message, title: 'Shift Report', subtitle: 'Mach, Continental, Custom', onTap: () {}),
          ToolCard(icon: Icons.precision_manufacturing, title: 'Equipment Status', subtitle: 'Bypassed/offline update', onTap: () => open(context, const EquipmentScreen())),
          const SectionTitle('🧰 Tools'),
          ToolCard(icon: Icons.assignment, title: 'JSA', subtitle: 'Dropdowns, employee rows, signatures', onTap: () => open(context, const JsaScreen())),
        ],
      ),
    );
  }
}
