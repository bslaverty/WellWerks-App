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

  Widget _hero(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A232F), Color(0xFF121821)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF2D3C4D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0x1FCDA56A),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.table_chart,
              color: Color(0xFFCDA56A),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tank Charts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reference strapping charts and field lookup tables in one clean list.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFCDA56A),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
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
          _hero(context),
          _sectionLabel('CHART REFERENCES'),
          ToolCard(
            icon: Icons.table_chart,
            title: 'FS3',
            subtitle: 'FS3 strapping chart',
            onTap: () => _open(context, 'FS3 Tank Chart', fs3Chart),
          ),
          const SizedBox(height: 8),
          ToolCard(
            icon: Icons.table_chart,
            title: 'SandX',
            subtitle: 'SandX G3 strapping chart',
            onTap: () => _open(context, 'SandX Tank Chart', sandXChart),
          ),
          const SizedBox(height: 8),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Flowback Tank - V Bottom',
            subtitle: 'Flowback V-bottom strapping chart',
            onTap: () =>
                _open(context, 'Flowback Tank - V Bottom', flowback500Chart),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Flowback Tank - MR 810039',
            subtitle: 'MR 810039 strapping chart',
            onTap: () => _open(
              context,
              'Flowback Tank (MR 810039)',
              mr810039FlowbackChart,
            ),
          ),
          const SizedBox(height: 8),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Gas Tank',
            subtitle: 'Menard gas tank stick chart',
            onTap: () => _open(context, 'Gas Tank', menardGasTankChart),
          ),
          const SizedBox(height: 8),
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
