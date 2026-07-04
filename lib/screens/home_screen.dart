import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'module_menu_screen.dart';
import 'rate_calculator_menu_screen.dart';
import 'bottoms_up_screen.dart';
import 'multiple_choke_screen.dart';
import 'gas_accum_screen.dart';
import 'production_inventory_screen.dart';
import 'production_dashboard_screen.dart';
import 'equipment_screen.dart';
import 'equipment_layout_screen.dart';
import 'jsa_screen.dart';
import 'active_shift_screen.dart';
import 'pressure_entry_screen.dart';
import 'shift_report_screen.dart';
import 'job_setup_screen.dart';
import 'report_template_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _moduleCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<ModuleTool> tools,
  }) {
    return ToolCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => open(context, ModuleMenuScreen(title: title, tools: tools)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(showBack: false),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Choose a module to start your shift, calculate rates, build reports, or manage layouts.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          _moduleCard(
            context: context,
            icon: Icons.dashboard,
            title: 'Dashboard',
            subtitle: 'Active job, quick round, shift summary',
            tools: const [
              ModuleTool(icon: Icons.work, title: 'New Job Setup', subtitle: 'Company, wells, equipment, tanks, report times', screen: JobSetupScreen()),
              ModuleTool(icon: Icons.dashboard_customize, title: 'Active Shift', subtitle: 'Current readings, attention cards, round history', screen: ActiveShiftScreen()),
              ModuleTool(icon: Icons.add_circle, title: 'Quick Round', subtitle: 'Enter production and pressure readings', screen: PressureEntryScreen()),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.build,
            title: 'Completions',
            subtitle: 'Bottoms up, rate calculator, choke tools',
            tools: const [
              ModuleTool(icon: Icons.speed, title: 'Rate Calculator', subtitle: 'FS3, SandX, 500 BBL Flowback, Production Tank', screen: RateCalculatorMenuScreen()),
              ModuleTool(icon: Icons.arrow_downward, title: 'Bottoms Up', subtitle: 'Pipe volume, lag time, estimated arrival', screen: BottomsUpScreen()),
              ModuleTool(icon: Icons.tune, title: 'Multiple Choke', subtitle: 'Equivalent choke size', screen: MultipleChokeScreen()),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.oil_barrel,
            title: 'Production',
            subtitle: 'Gas accum, reports, tanks, text updates',
            tools: const [
              ModuleTool(icon: Icons.dashboard, title: 'Production Dashboard', subtitle: 'Gas, rounds, inventory, reports, and text updates', screen: ProductionDashboardScreen()),
              ModuleTool(icon: Icons.local_fire_department, title: 'Gas Accum Calculator', subtitle: 'Hourly gas accumulation', screen: GasAccumScreen()),
              ModuleTool(icon: Icons.add_circle, title: 'Quick Round', subtitle: 'Production and pressure readings', screen: PressureEntryScreen()),
              ModuleTool(icon: Icons.inventory, title: 'Production Inventory', subtitle: 'Oil, water, hauled, pumped, on location', screen: ProductionInventoryScreen()),
              ModuleTool(icon: Icons.message, title: 'Shift Report', subtitle: 'Mach, Continental, Custom', screen: ShiftReportScreen()),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.account_tree,
            title: 'Layouts',
            subtitle: 'Equipment layout designer and saved rig-ups',
            tools: const [
              ModuleTool(icon: Icons.precision_manufacturing, title: 'Equipment Status', subtitle: 'Bypassed/offline update', screen: EquipmentScreen()),
              ModuleTool(icon: Icons.account_tree, title: 'Equipment Layout Designer', subtitle: 'Drag, drop, connect with iron', screen: EquipmentLayoutScreen()),
              ModuleTool(icon: Icons.folder, title: 'Saved Layouts', subtitle: 'Saved rig-ups and facility layouts'),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.assignment,
            title: 'Safety',
            subtitle: 'JSA and safety documents',
            tools: const [
              ModuleTool(icon: Icons.assignment, title: 'JSA', subtitle: 'Dropdowns, employee rows, signatures', screen: JsaScreen()),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.settings,
            title: 'Settings',
            subtitle: 'Tank charts, pipe database, company defaults',
            tools: const [
              ModuleTool(icon: Icons.table_chart, title: 'Tank Charts', subtitle: 'FS3, SandX, Flowback charts'),
              ModuleTool(icon: Icons.straighten, title: 'Pipe Database', subtitle: 'Pipe capacities for Bottoms Up'),
              ModuleTool(icon: Icons.business, title: 'Company Defaults', subtitle: 'Report formats and customer settings'),
            ],
          ),
        ],
      ),
    );
  }
}
