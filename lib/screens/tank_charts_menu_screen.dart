import 'package:flutter/material.dart';

import '../data/tank_charts.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'chart_reference_screen.dart';

class TankChartsMenuScreen extends StatelessWidget {
  const TankChartsMenuScreen({super.key});

  void _open(BuildContext context, String title, TankChart chart) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChartReferenceScreen.tankChart(
          title: title,
          chart: chart,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Tank Charts', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Tank Charts subsection. Use one-tap cards for each tank chart.',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 12),
          ToolCard(
            icon: Icons.table_chart,
            title: 'FS3',
            subtitle: 'FS3 strapping chart',
            onTap: () => _open(context, 'FS3 Tank Chart', fs3Chart),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'SandX',
            subtitle: 'SandX G3 strapping chart',
            onTap: () => _open(context, 'SandX Tank Chart', sandXChart),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Flowback Tank - V Bottom',
            subtitle: 'Flowback V-bottom strapping chart',
            onTap: () =>
                _open(context, 'Flowback Tank - V Bottom', flowback500Chart),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Flowback Tank - Round Bottom',
            subtitle: 'Flowback round-bottom strapping chart',
            onTap: () => _open(
              context,
              'Flowback Tank - Round Bottom',
              flowbackRoundBottomChart,
            ),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Gas Tank',
            subtitle: 'Menard gas tank stick chart',
            onTap: () => _open(context, 'Gas Tank', menardGasTankChart),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Production Tank',
            subtitle: 'Default production tank reference values',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const ChartReferenceScreen.productionTankReference(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
