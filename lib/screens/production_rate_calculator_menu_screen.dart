import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import '../widgets/ww_number_field.dart';
import 'rate_calculator_screen.dart';

class ProductionRateCalculatorMenuScreen extends StatefulWidget {
  const ProductionRateCalculatorMenuScreen({super.key});

  @override
  State<ProductionRateCalculatorMenuScreen> createState() =>
      _ProductionRateCalculatorMenuScreenState();
}

class _ProductionRateCalculatorMenuScreenState
    extends State<ProductionRateCalculatorMenuScreen> {
  final TextEditingController _productionTankFactorController =
      TextEditingController(text: '1.67');

  @override
  void dispose() {
    _productionTankFactorController.dispose();
    super.dispose();
  }

  void _open(BuildContext context, RateCalculatorConfig config) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RateCalculatorScreen(config: config)),
    );
  }

  RateCalculatorConfig _productionTankConfig() {
    final factor =
        double.tryParse(_productionTankFactorController.text.trim()) ?? 1.67;
    return RateCalculatorConfig.linear(
      'Production Tank',
      defaultFactor: factor,
      storageId: 'production_tank_linear',
      allowOperationsLogAutoSave: false,
      rateLogEnabledByDefault: true,
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
            icon: Icons.speed,
            title: 'Flowback Tank (MR 810039)',
            subtitle: 'MR 810039 production-only rate + log',
            onTap: () => _open(
              context,
              const RateCalculatorConfig.chart(
                'Flowback Tank (MR 810039)',
                'mr_810039',
                storageId: 'mr_810039',
                rateLogEnabledByDefault: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          WwNumberField(
            label: 'Production Tank Factor (BBL/In)',
            controller: _productionTankFactorController,
            helperText:
                'Default: 1.67. Change this if your production tank factor is different.',
            allowDecimal: true,
          ),
          const SizedBox(height: 8),
          ToolCard(
            icon: Icons.oil_barrel,
            title: 'Production Tank',
            subtitle: 'Default 1.67 BBL/in, editable, production-only rate log',
            onTap: () => _open(context, _productionTankConfig()),
          ),
        ],
      ),
    );
  }
}
