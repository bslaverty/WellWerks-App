import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'gas_accum_screen.dart';
import 'pressure_entry_screen.dart';
import 'production_inventory_screen.dart';
import 'report_template_screen.dart';
import 'shift_report_screen.dart';
import 'text_update_screen.dart';

class ProductionDashboardScreen extends StatelessWidget {
  const ProductionDashboardScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Production', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Production tools for gas rates, tank inventory, quick rounds, and copy/paste updates.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 14),
          ToolCard(
            icon: Icons.local_fire_department,
            title: 'Gas Accum Calculator',
            subtitle: '13 readings with hourly gas-rate answers',
            onTap: () => _open(context, const GasAccumScreen()),
          ),
          ToolCard(
            icon: Icons.add_circle,
            title: 'Quick Round',
            subtitle: 'Production and pressure readings in one place',
            onTap: () => _open(context, const PressureEntryScreen()),
          ),
          ToolCard(
            icon: Icons.inventory,
            title: 'Production Inventory',
            subtitle: 'Oil, water, hauled, pumped, and on location',
            onTap: () => _open(context, const ProductionInventoryScreen()),
          ),
          ToolCard(
            icon: Icons.message,
            title: 'Shift Report',
            subtitle: 'Build and copy a clean report from latest round',
            onTap: () => _open(context, const ShiftReportScreen()),
          ),
          ToolCard(
            icon: Icons.sms,
            title: 'Text Update Builder',
            subtitle: 'Build a quick copy/paste production update',
            onTap: () => _open(context, const TextUpdateScreen()),
          ),
          ToolCard(
            icon: Icons.edit_note,
            title: 'Report Builder',
            subtitle: 'Custom report fields and required fields',
            onTap: () => _open(context, const ReportTemplateScreen()),
          ),
        ],
      ),
    );
  }
}
