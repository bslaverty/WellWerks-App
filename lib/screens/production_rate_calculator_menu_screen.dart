import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'rate_calculator_screen.dart';

class ProductionRateCalculatorMenuScreen extends StatelessWidget {
  const ProductionRateCalculatorMenuScreen({super.key});

  void _open(BuildContext context, RateCalculatorConfig config) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RateCalculatorScreen(config: config)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          const AppHeader(title: 'Production Rate Calculator', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Standalone production calculator. Uses production-only logs and does not send data to Quick Round or production reports.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          ToolCard(
            icon: Icons.speed,
            title: 'V-Bottom',
            subtitle: 'Production-only rate + log (no FS3 / SandX)',
            onTap: () => _open(
              context,
              const RateCalculatorConfig.chart(
                'Production V-Bottom',
                'flowback500',
                storageId: 'production_flowback500',
                allowOperationsLogAutoSave: false,
                rateLogEnabledByDefault: true,
              ),
            ),
          ),
          ToolCard(
            icon: Icons.speed,
            title: 'Round Bottom',
            subtitle: 'Production-only rate + log (no FS3 / SandX)',
            onTap: () => _open(
              context,
              const RateCalculatorConfig.chart(
                'Production Round Bottom',
                'flowback_round_bottom',
                storageId: 'production_flowback_round_bottom',
                allowOperationsLogAutoSave: false,
                rateLogEnabledByDefault: true,
              ),
            ),
          ),
          ToolCard(
            icon: Icons.oil_barrel,
            title: 'Production Tank',
            subtitle: 'Default 1.67 BBL/in, production-only rate log',
            onTap: () => _open(
              context,
              const RateCalculatorConfig.linear(
                'Production Tank',
                defaultFactor: 1.67,
                storageId: 'production_tank_linear',
                allowOperationsLogAutoSave: false,
                rateLogEnabledByDefault: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
