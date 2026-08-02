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
            child: const Icon(Icons.speed, color: Color(0xFFCDA56A), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Production Rate Calculator',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Production-only rate tools and logs that stay separate from Quick Round and reports.',
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
      appBar:
          const AppHeader(title: 'Production Rate Calculator', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _hero(context),
          _sectionLabel('TANK OPTIONS'),
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
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
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
          const SizedBox(height: 10),
          _sectionLabel('CUSTOM FACTOR'),
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
