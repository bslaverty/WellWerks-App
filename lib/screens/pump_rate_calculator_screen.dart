import 'package:flutter/material.dart';

import 'rate_calculator_screen.dart';

class PumpRateCalculatorScreen extends StatelessWidget {
  const PumpRateCalculatorScreen({super.key});

  static const List<RateCalculatorConfig> _pumpRateConfigs = [
    RateCalculatorConfig.chart('Flowback Tank', 'flowback500'),
    RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
    RateCalculatorConfig.chart('SandX G3', 'sandx'),
    RateCalculatorConfig.linear(
      'Production Tank',
      defaultFactor: 1.67,
      storageId: 'production_tank_linear',
      allowOperationsLogAutoSave: false,
      rateLogEnabledByDefault: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const RateCalculatorScreen(
      config: RateCalculatorConfig.chart('Flowback Tank', 'flowback500'),
      homeMultiMode: true,
      availableConfigs: _pumpRateConfigs,
    );
  }
}
