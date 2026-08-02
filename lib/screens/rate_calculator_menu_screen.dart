import 'package:flutter/material.dart';
import '../services/rate_calculator_session_service.dart';
import '../services/rate_timer_service.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'rate_calculator_screen.dart';

class RateCalculatorMenuScreen extends StatelessWidget {
  final bool homeMultiMode;
  static final _sessionService = RateCalculatorSessionService.instance;
  static final _timerService = RateTimerService();
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

  String _calculatorIdForConfig(RateCalculatorConfig config) {
    return (config.storageId ?? config.chartId ?? config.title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  Future<void> _open(BuildContext context, RateCalculatorConfig config) async {
    String? instanceId;
    if (homeMultiMode) {
      final calculatorId = _calculatorIdForConfig(config);
      await _sessionService.ensureInitialized();
      final activeTimer =
          await _timerService.loadActiveTimerForCalculator(calculatorId);
      instanceId = activeTimer?.instanceId.isNotEmpty == true
          ? activeTimer!.instanceId
          : _sessionService.sessionKeyForCalculator(calculatorId);
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RateCalculatorScreen(
          config: config,
          instanceId: instanceId,
          homeMultiMode: homeMultiMode,
          availableConfigs: homeMultiMode ? _menuConfigs : null,
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
            child: const Icon(Icons.speed, color: Color(0xFFCDA56A), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rate Calculator',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a tank chart to calculate BBL/min, BBL/hr, and BBL/day.',
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
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppHeader(title: 'Rate Calculator', showBack: true),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _hero(context),
            _sectionLabel('FLOWBACK & PRODUCTION TANKS'),
            ToolCard(
              icon: Icons.speed,
              title: 'FS3 Tank',
              subtitle: 'Falcon FS3 strapping chart',
              onTap: () => _open(
                context,
                const RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
              ),
            ),
            const SizedBox(height: 8),
            ToolCard(
              icon: Icons.speed,
              title: 'SandX G3',
              subtitle: 'SandX G3 hopper chart',
              onTap: () => _open(context,
                  const RateCalculatorConfig.chart('SandX G3', 'sandx')),
            ),
            const SizedBox(height: 8),
            ToolCard(
              icon: Icons.speed,
              title: 'V-Bottom',
              subtitle: 'V-bottom strapping chart',
              onTap: () => _open(context,
                  const RateCalculatorConfig.chart('V-Bottom', 'flowback500')),
            ),
            const SizedBox(height: 8),
            ToolCard(
              icon: Icons.speed,
              title: 'Round Bottom',
              subtitle: 'Round-bottom strapping chart',
              onTap: () => _open(
                  context,
                  const RateCalculatorConfig.chart(
                      'Round Bottom', 'flowback_round_bottom')),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
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
