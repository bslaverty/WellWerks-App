import 'package:flutter/material.dart';

import 'rate_calculator_screen.dart';

class PumpRateCalculatorScreen extends StatelessWidget {
  const PumpRateCalculatorScreen({super.key});

  static const List<RateCalculatorConfig> _pumpRateConfigs = [
    RateCalculatorConfig.chart(
      'Flowback Tank (V-Bottom)',
      'flowback500',
      storageId: 'pump_flowback500',
      reverseGaugeDelta: true,
      allowOperationsLogAutoSave: false,
      rateLogEnabledByDefault: true,
    ),
    RateCalculatorConfig.chart(
      'Flowback Tank (Round Bottom)',
      'flowback_round_bottom',
      storageId: 'pump_flowback_round_bottom',
      reverseGaugeDelta: true,
      allowOperationsLogAutoSave: false,
      rateLogEnabledByDefault: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const RateCalculatorScreen(
      config: RateCalculatorConfig.chart(
        'Flowback Tank (V-Bottom)',
        'flowback500',
        storageId: 'pump_flowback500',
        reverseGaugeDelta: true,
        allowOperationsLogAutoSave: false,
        rateLogEnabledByDefault: true,
      ),
      homeMultiMode: true,
      homeTabsStorageKey: 'wellwerks_pump_rate_tabs_v1',
      availableConfigs: _pumpRateConfigs,
    );
  }
}
