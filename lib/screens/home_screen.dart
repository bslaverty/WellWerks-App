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
import 'shift_report_screen.dart';
import 'job_setup_screen.dart';
import 'report_template_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  bool _matches(String title, String subtitle) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) || subtitle.toLowerCase().contains(q);
  }

  Widget _tool({required IconData icon, required String title, required String subtitle, required Widget screen}) {
    if (!_matches(title, subtitle)) return const SizedBox.shrink();
    return ToolCard(icon: icon, title: title, subtitle: subtitle, onTap: () => open(context, screen));
  }

  Widget _placeholderTool({required IconData icon, required String title, required String subtitle}) {
    if (!_matches(title, subtitle)) return const SizedBox.shrink();
    return ToolCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title is on the build list.')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(showBack: false),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search toolbox',
              hintText: 'gas, tank, flange, report...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          const SectionTitle('Favorites'),
          Wrap(spacing: 10, runSpacing: 10, children: const [
            Chip(label: Text('Quick Round')),
            Chip(label: Text('FS3 Rate')),
            Chip(label: Text('Gas Accum')),
            Chip(label: Text('Shift Report')),
          ]),
          const SectionTitle('⚡ Shift'),
          _tool(icon: Icons.work, title: 'New Job Setup', subtitle: 'Company, wells, equipment, tanks, report times', screen: const JobSetupScreen()),
          _tool(icon: Icons.dashboard_customize, title: 'Active Shift', subtitle: 'Current readings, attention cards, and round history', screen: const ActiveShiftScreen()),
          _tool(icon: Icons.add_circle, title: 'Quick Round', subtitle: 'Enter production and pressure readings once', screen: const PressureEntryScreen()),
          const SectionTitle('🌊 Flowback'),
          _tool(icon: Icons.speed, title: 'FS3 Rate', subtitle: 'Use FS3 tank chart', screen: const RateCalculatorScreen(tankName: 'FS3')),
          _tool(icon: Icons.speed, title: 'SandX Rate', subtitle: 'Use SandX tank chart', screen: const RateCalculatorScreen(tankName: 'SandX')),
          _tool(icon: Icons.speed, title: 'Flowback Tank Rate', subtitle: 'Use Flowback tank chart', screen: const RateCalculatorScreen(tankName: 'Flowback')),
          _placeholderTool(icon: Icons.arrow_downward, title: 'Bottoms Up', subtitle: 'Pipe volume and lag time'),
          _placeholderTool(icon: Icons.tune, title: 'Multiple Choke', subtitle: 'Equivalent choke size'),
          _placeholderTool(icon: Icons.water_drop, title: 'Chlorides', subtitle: 'Chloride calculations'),
          const SectionTitle('🛢 Production'),
          _tool(icon: Icons.local_fire_department, title: 'Gas Accum', subtitle: 'Hourly gas accumulation', screen: const GasAccumScreen()),
          _tool(icon: Icons.oil_barrel, title: 'Production Tank', subtitle: 'Editable Tank Factor, default 1.67', screen: const ProductionTankScreen()),
          _tool(icon: Icons.inventory, title: 'Production Inventory', subtitle: 'Produced, hauled, pumped, on location', screen: const ProductionInventoryScreen()),
          const SectionTitle('📚 Charts'),
          _placeholderTool(icon: Icons.grid_on, title: 'Sand Chart', subtitle: 'Reference chart'),
          _placeholderTool(icon: Icons.settings_input_component, title: 'Flange Chart', subtitle: 'Reference chart'),
          _placeholderTool(icon: Icons.table_chart, title: 'Tank Charts', subtitle: 'FS3, SandX, Flowback'),
          const SectionTitle('📋 Reports'),
          _tool(icon: Icons.message, title: 'Shift Report', subtitle: 'Mach, Continental, Custom', screen: const ShiftReportScreen()),
          _tool(icon: Icons.edit_note, title: 'Report Builder', subtitle: 'Pick fields, required fields, and order for Custom', screen: const ReportTemplateScreen()),
          _tool(icon: Icons.precision_manufacturing, title: 'Equipment Status', subtitle: 'Bypassed/offline update', screen: const EquipmentScreen()),
          const SectionTitle('🧰 Tools'),
          _tool(icon: Icons.assignment, title: 'JSA', subtitle: 'Dropdowns, employee rows, signatures', screen: const JsaScreen()),
        ],
      ),
    );
  }
}
