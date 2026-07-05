import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'gas_accum_screen.dart';
import 'pressure_entry_screen.dart';
import 'production_history_screen.dart';
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
            title: 'Text/Report Layouts',
            subtitle: 'Production Inventory plus report/text layout profiles',
            onTap: () => _open(context,
                const ReportTemplateScreen(initialSection: 'inventory')),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Production Report',
            subtitle: 'Read-only saved hourly table for the active shift',
            onTap: () => _open(context, const ShiftReportScreen()),
          ),
          ToolCard(
            icon: Icons.sms,
            title: 'Text Update',
            subtitle: 'Select an hour, preview, and copy the text update',
            onTap: () => _open(context, const TextUpdateScreen()),
          ),
          ToolCard(
            icon: Icons.history,
            title: 'Production History',
            subtitle:
                'Archived inventory, reports, hourly checks, and text updates',
            onTap: () => _open(context, const ProductionHistoryScreen()),
          ),
          ToolCard(
            icon: Icons.edit_note,
            title: 'Layout Profiles',
            subtitle: 'Create and manage reusable layout profiles',
            onTap: () => _open(context, const ReportTemplateScreen()),
          ),
        ],
      ),
    );
  }
}
