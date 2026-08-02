import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'rate_calculator_screen.dart';

class RateCalculatorMenuScreen extends StatelessWidget {
  final bool homeMultiMode;
  const RateCalculatorMenuScreen({super.key, this.homeMultiMode = false});

  static const List<RateCalculatorConfig> _menuConfigs = [
    RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
    RateCalculatorConfig.chart('SandX G3', 'sandx'),
    RateCalculatorConfig.chart('V-Bottom', 'flowback500'),
    RateCalculatorConfig.chart('Round Bottom', 'flowback_round_bottom'),
    RateCalculatorConfig.chart(
      'Flowback Tank (MR 810039)',
      'mr_810039',
      storageId: 'mr_810039',
    ),
    RateCalculatorConfig.linear('Production Tank', defaultFactor: 1.67),
  ];

  void _open(BuildContext context, RateCalculatorConfig config) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RateCalculatorScreen(
          config: config,
          homeMultiMode: homeMultiMode,
          availableConfigs: homeMultiMode ? _menuConfigs : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppHeader(title: 'Rate Calculator', showBack: true),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Choose a tank. Results show BBL/min, BBL/hr, and BBL/day only.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            ToolCard(
              icon: Icons.speed,
              title: 'FS3 Tank',
              subtitle: 'Falcon FS3 strapping chart',
              onTap: () => _open(
                context,
                const RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
              ),
            ),
            ToolCard(
              icon: Icons.speed,
              title: 'SandX G3',
              subtitle: 'SandX G3 hopper chart',
              onTap: () => _open(context,
                  const RateCalculatorConfig.chart('SandX G3', 'sandx')),
            ),
            ToolCard(
              icon: Icons.speed,
              title: 'V-Bottom',
              subtitle: 'V-bottom strapping chart',
              onTap: () => _open(context,
                  const RateCalculatorConfig.chart('V-Bottom', 'flowback500')),
            ),
            ToolCard(
              icon: Icons.speed,
              title: 'Round Bottom',
              subtitle: 'Round-bottom strapping chart',
              onTap: () => _open(
                  context,
                  const RateCalculatorConfig.chart(
                      'Round Bottom', 'flowback_round_bottom')),
            ),
            ToolCard(
              icon: Icons.speed,
              title: 'Flowback Tank (MR 810039)',
              subtitle: 'MR 810039 strapping chart',
              onTap: () => _open(
                context,
                const RateCalculatorConfig.chart(
                  'Flowback Tank (MR 810039)',
                  'mr_810039',
                  storageId: 'mr_810039',
                ),
              ),
            ),
            ToolCard(
              icon: Icons.oil_barrel,
              title: 'Production Tank',
              subtitle: 'Default 1.67 BBL/in, editable',
              onTap: () => _open(
                  context,
                  const RateCalculatorConfig.linear('Production Tank',
                      defaultFactor: 1.67)),
            ),
          ],
        ),
      );
}
