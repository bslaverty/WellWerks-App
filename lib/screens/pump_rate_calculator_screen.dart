import 'package:flutter/material.dart';

import 'rate_calculator_screen.dart';

class PumpRateCalculatorScreen extends StatelessWidget {
  const PumpRateCalculatorScreen({super.key});

  static const List<RateCalculatorConfig> _pumpRateConfigs = [
    RateCalculatorConfig.chart('Flowback Tank (V-Bottom)', 'flowback500'),
    RateCalculatorConfig.chart(
      'Flowback Tank (Round Bottom)',
      'flowback_round_bottom',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const RateCalculatorScreen(
      config: RateCalculatorConfig.chart(
        'Flowback Tank (V-Bottom)',
        'flowback500',
      ),
      homeMultiMode: true,
      availableConfigs: _pumpRateConfigs,
    );
  }
}
