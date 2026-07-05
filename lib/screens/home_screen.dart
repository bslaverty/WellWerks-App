import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'module_menu_screen.dart';
import 'rate_calculator_menu_screen.dart';
import 'equipment_layout_screen.dart';
import 'jsa_screen.dart';
import 'pressure_entry_screen.dart';
import 'shift_report_screen.dart';
import 'report_template_screen.dart';
import 'text_update_screen.dart';
import 'production_history_screen.dart';
import 'gas_accum_screen.dart';
import 'bottoms_up_screen.dart';
import 'multiple_choke_screen.dart';
import 'chart_reference_screen.dart';
import '../data/tank_charts.dart';
import 'conversion_calculator_screen.dart';
import 'settings_screen.dart';
import 'about_support_screen.dart';
import 'job_setup_screen.dart';

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
      onTap: () => open(
        context,
        ModuleMenuScreen(
          title: title,
          tools: tools,
          showHomeButton: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        showBack: false,
        trailingActions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'jobSetup') {
                open(context, const JobSetupScreen());
                return;
              }
              if (value == 'settings') {
                open(context, const SettingsScreen());
                return;
              }
              if (value == 'about') {
                open(context, const AboutSupportScreen());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'jobSetup',
                child: Text('Job Setup'),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text('Settings'),
              ),
              PopupMenuItem(
                value: 'about',
                child: Text('About & Support'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Choose a module for production, completions, charts, layouts, and safety.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          _moduleCard(
            context: context,
            icon: Icons.oil_barrel,
            title: 'Production',
            subtitle: 'Quick Round, reports, text updates, and layouts',
            tools: const [
              ModuleTool(
                icon: Icons.add_circle,
                title: 'Quick Round',
                subtitle: 'Enter production and pressure readings',
                screen: PressureEntryScreen(),
              ),
              ModuleTool(
                icon: Icons.table_chart,
                title: 'Production Report',
                subtitle: 'Read-only saved hourly production table',
                screen: ShiftReportScreen(),
              ),
              ModuleTool(
                icon: Icons.sms,
                title: 'Text Update',
                subtitle: 'Select an hour and copy a text update',
                screen: TextUpdateScreen(),
              ),
              ModuleTool(
                icon: Icons.edit_note,
                title: 'Text/Report Layouts',
                subtitle: 'Production Inventory and layout profile setup',
                screen: ReportTemplateScreen(initialSection: 'inventory'),
              ),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.build,
            title: 'Completions',
            subtitle: 'Field calculators for pumping and choke operations',
            tools: const [
              ModuleTool(
                icon: Icons.speed,
                title: 'Rate Calculator',
                subtitle: 'FS3, SandX, flowback, and production rate tools',
                screen: RateCalculatorMenuScreen(),
              ),
              ModuleTool(
                icon: Icons.local_fire_department,
                title: 'Gas Accum Calculator',
                subtitle: 'Hourly gas rate from totalizer readings',
                screen: GasAccumScreen(),
              ),
              ModuleTool(
                icon: Icons.arrow_downward,
                title: 'Bottoms Up Calculator',
                subtitle: 'Pipe volume, lag time, and ETA',
                screen: BottomsUpScreen(),
              ),
              ModuleTool(
                icon: Icons.tune,
                title: 'Multiple Choke Calculator',
                subtitle: 'Equivalent choke and total flow area',
                screen: MultipleChokeScreen(),
              ),
              ModuleTool(
                icon: Icons.straighten,
                title: 'Conversion Calculator',
                subtitle: 'Length, volume, pressure, flow, gas, and oilfield',
                screen: ConversionCalculatorScreen(),
              ),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.bar_chart,
            title: 'Charts',
            subtitle: 'Tank and field chart references',
            tools: [
              ModuleTool(
                icon: Icons.table_chart,
                title: 'FS3 Tank Chart',
                subtitle: 'FS3 strapping chart reference',
                screen: ChartReferenceScreen.tankChart(
                  title: 'FS3 Tank Chart',
                  chart: fs3Chart,
                ),
              ),
              ModuleTool(
                icon: Icons.table_chart,
                title: 'SandX Tank Chart',
                subtitle: 'SandX G3 strapping chart reference',
                screen: ChartReferenceScreen.tankChart(
                  title: 'SandX Tank Chart',
                  chart: sandXChart,
                ),
              ),
              ModuleTool(
                icon: Icons.table_chart,
                title: 'Flowback Tank Chart',
                subtitle: '500 BBL flowback tank chart reference',
                screen: ChartReferenceScreen.tankChart(
                  title: 'Flowback Tank Chart',
                  chart: flowback500Chart,
                ),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Production Tank Chart',
                subtitle: 'Default production tank reference values',
                screen: ChartReferenceScreen.productionTankReference(),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Chlorides Chart',
                subtitle: 'Field chloride reference chart',
                screen: ChartReferenceScreen(
                  title: 'Chlorides Chart',
                  description:
                      'Chlorides reference table from the web app source with Brix to SG conversion.',
                  showBrixTool: true,
                  showChloridesCalculator: true,
                  enableSearch: true,
                  sections: [
                    ChartSection(
                      title: 'Water Weight and Chlorides',
                      columns: ['SP.GR.', '#/G', 'CLPPM'],
                      rows: [
                        ['1.002', '8.36', '1755'],
                        ['1.004', '8.38', '3511'],
                        ['1.006', '8.40', '5267'],
                        ['1.008', '8.41', '7023'],
                        ['1.010', '8.43', '8779'],
                        ['1.086', '9.06', '75500'],
                        ['1.088', '9.08', '77260'],
                        ['1.090', '9.10', '79010'],
                        ['1.092', '9.11', '80770'],
                        ['1.170', '9.76', '149200'],
                        ['1.172', '9.78', '151000'],
                        ['1.174', '9.80', '152700'],
                        ['1.176', '9.81', '154501'],
                      ],
                    ),
                    ChartSection(
                      title: 'Brix to SG Reference',
                      columns: ['Brix', 'SG'],
                      rows: [
                        ['0', '1.0000'],
                        ['5', '1.0197'],
                        ['10', '1.0400'],
                        ['15', '1.0607'],
                        ['20', '1.0829'],
                        ['25', '1.1068'],
                        ['30', '1.1325'],
                      ],
                    ),
                  ],
                ),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Tubing Chart',
                subtitle: 'Tubing and casing capacity reference',
                screen: ChartReferenceScreen(
                  title: 'Tubing Chart',
                  description:
                      'Tubing and casing dimensional rows captured from the web app tubing sheet.',
                  enableSearch: true,
                  sections: [
                    ChartSection(
                      title: 'Tubing',
                      columns: ['OD', 'Lbs/ft', 'ID'],
                      rows: [
                        ['1.050', '1.2', '0.824'],
                        ['1.050', '1.5', '0.742'],
                        ['1.315', '1.8', '1.049'],
                        ['1.660', '2.4', '1.38'],
                        ['1.900', '2.9', '1.61'],
                        ['2.375', '4.7', '1.995'],
                        ['2.375', '5.95', '1.867'],
                        ['2.875', '6.5', '2.441'],
                        ['2.875', '8.7', '2.259'],
                        ['3.500', '9.3', '2.992'],
                        ['3.500', '12.95', '2.75'],
                        ['4.000', '11', '3.476'],
                        ['4.500', '12.75', '3.958'],
                      ],
                    ),
                    ChartSection(
                      title: 'Casing',
                      columns: ['OD', 'Lbs/ft', 'ID'],
                      rows: [
                        ['5.500', '15.5', '4.95'],
                        ['5.500', '17', '4.892'],
                        ['5.500', '20', '4.778'],
                        ['5.500', '23', '4.67'],
                        ['5.500', '26', '4.548'],
                        ['5.750', '14', '5.29'],
                        ['5.750', '17', '5.19'],
                        ['5.750', '19.5', '5.09'],
                        ['6.000', '15', '5.524'],
                        ['6.000', '20', '5.352'],
                        ['6.625', '13', '6.255'],
                        ['6.625', '20', '6.049'],
                        ['6.625', '32', '5.675'],
                      ],
                    ),
                  ],
                ),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Sand Chart',
                subtitle: 'Sand measurement and weight reference',
                screen: ChartReferenceScreen(
                  title: 'Sand Chart',
                  description:
                      'Sand measurement and weight tables from the web app sand sheet.',
                  enableSearch: true,
                  sections: [
                    ChartSection(
                      title: 'Sand Measurement',
                      columns: ['From', '=', 'To'],
                      rows: [
                        ['1 Gallon', '=', '4 Quarts'],
                        ['1 Quart', '=', '4 Cups'],
                        ['1 Quart', '=', '2 Pints'],
                        ['1 Pint', '=', '2 Cups'],
                        ['1 Cup', '=', '16 Tblsp'],
                        ['1/2 Cup', '=', '8 Tblsp'],
                        ['1/4 Cup', '=', '4 Tblsp'],
                        ['1 Tblsp', '=', '3 Tsp'],
                      ],
                    ),
                    ChartSection(
                      title: 'Sand Weight',
                      columns: ['From', '=', 'Weight'],
                      rows: [
                        ['1 Bbl', '=', '756 lbs'],
                        ['1/2 Bbl', '=', '378 lbs'],
                        ['1/4 Bbl', '=', '189 lbs'],
                        ['1 Gal', '=', '18 lbs'],
                        ['1/2 Gal', '=', '9 lbs'],
                        ['1/4 Gal', '=', '4.5 lbs'],
                        ['1 Pint', '=', '2.3 lbs'],
                        ['1 Cup', '=', '1.1 lbs'],
                        ['1/2 Cup', '=', '0.55 lbs'],
                        ['1 Tblsp', '=', '0.07 lbs'],
                      ],
                    ),
                  ],
                ),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Flanges Chart',
                subtitle: 'Flange pressure, gasket, studs, and wrench sizes',
                screen: ChartReferenceScreen(
                  title: 'Flanges Chart',
                  description:
                      'Flange table rows captured from the web app flange sheet.',
                  enableSearch: true,
                  sections: [
                    ChartSection(
                      title: 'Flanges',
                      columns: [
                        'Flange Size',
                        'Pressure',
                        'Ring Gasket',
                        'No. Studs',
                        'Stud Size',
                        'Nut Size',
                        'Oteco Wrench'
                      ],
                      rows: [
                        [
                          '1-11/16"',
                          '10000',
                          'BX-150',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '1-11/16"',
                          '15000',
                          'BX-150',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '1-13/16"',
                          '10000',
                          'BX-151',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '1-13/16"',
                          '15000',
                          'BX-151',
                          '8',
                          '7/8"',
                          '1-7/16"',
                          '7/8"'
                        ],
                        [
                          '1-13/16"',
                          '20000',
                          'BX-151',
                          '8',
                          '1"',
                          '1-5/8"',
                          '1"'
                        ],
                        [
                          '2-1/16"',
                          '10000',
                          'BX-152',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '2-1/16"',
                          '15000',
                          'BX-152',
                          '8',
                          '7/8"',
                          '1-7/16"',
                          '7/8"'
                        ],
                        [
                          '2-1/16"',
                          '20000',
                          'BX-152',
                          '8',
                          '1-1/8"',
                          '1-13/16"',
                          '1-1/8"'
                        ],
                        [
                          '2-9/16"',
                          '10000',
                          'BX-153',
                          '8',
                          '7/8"',
                          '1-7/16"',
                          '7/8"'
                        ],
                        [
                          '2-9/16"',
                          '15000',
                          'BX-153',
                          '8',
                          '1"',
                          '1-5/8"',
                          '1"'
                        ],
                        [
                          '2-9/16"',
                          '20000',
                          'BX-153',
                          '8',
                          '1-1/4"',
                          '2"',
                          '1-1/4"'
                        ],
                        [
                          '3-1/16"',
                          '10000',
                          'BX-154',
                          '8',
                          '1"',
                          '1-5/8"',
                          '1"'
                        ],
                        [
                          '3-1/16"',
                          '15000',
                          'BX-154',
                          '8',
                          '1-1/8"',
                          '1-13/16"',
                          '1-1/8"'
                        ],
                        [
                          '3-1/16"',
                          '20000',
                          'BX-154',
                          '8',
                          '1-3/8"',
                          '2-3/16"',
                          '1-3/8"'
                        ],
                        [
                          '4-1/16"',
                          '10000',
                          'BX-155',
                          '8',
                          '1-1/8"',
                          '1-13/16"',
                          '1-1/8"'
                        ],
                        [
                          '4-1/16"',
                          '15000',
                          'BX-155',
                          '8',
                          '1-3/8"',
                          '2-3/16"',
                          '1-3/8"'
                        ],
                        [
                          '4-1/16"',
                          '20000',
                          'BX-155',
                          '8',
                          '1-3/4"',
                          '2-3/4"',
                          '1-3/4"'
                        ],
                        [
                          '7-1/16"',
                          '10000',
                          'BX-156',
                          '12',
                          '1-1/2"',
                          '2-3/8"',
                          '1-1/2"'
                        ],
                        [
                          '7-1/16"',
                          '15000',
                          'BX-156',
                          '16',
                          '1-1/2"',
                          '2-3/8"',
                          '1-1/2"'
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          ToolCard(
            icon: Icons.account_tree,
            title: 'Layout Designer',
            subtitle: 'Build and manage field equipment layouts',
            onTap: () => open(context, const EquipmentLayoutScreen()),
          ),
          ToolCard(
            icon: Icons.assignment,
            title: 'JSA',
            subtitle: 'Safety worksheet, crew rows, and signatures',
            onTap: () => open(context, const JsaScreen()),
          ),
          ToolCard(
            icon: Icons.history,
            title: 'History',
            subtitle: 'Search archived jobs and past shift records',
            onTap: () => open(context, const ProductionHistoryScreen()),
          ),
        ],
      ),
    );
  }
}
