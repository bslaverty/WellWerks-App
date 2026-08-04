import 'package:flutter/material.dart';

import '../services/rate_calculator_session_service.dart';
import '../services/rate_timer_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';
import 'rate_calculator_screen.dart';

class RateCalculatorMenuScreen extends StatefulWidget {
  final bool homeMultiMode;

  const RateCalculatorMenuScreen({super.key, this.homeMultiMode = false});

  @override
  State<RateCalculatorMenuScreen> createState() =>
      _RateCalculatorMenuScreenState();
}

class _RateCalculatorMenuScreenState extends State<RateCalculatorMenuScreen> {
  static final _sessionService = RateCalculatorSessionService.instance;
  static final _timerService = RateTimerService();

  static const List<RateCalculatorConfig> _menuConfigs =
      kProductionRateCalculatorConfigs;

  final TextEditingController _productionTankFactorController =
      TextEditingController(text: '1.67');

  late RateCalculatorConfig _selectedConfig;

  @override
  void initState() {
    super.initState();
    _selectedConfig = _menuConfigs.first;
  }

  @override
  void dispose() {
    _productionTankFactorController.dispose();
    super.dispose();
  }

  String _calculatorIdForConfig(RateCalculatorConfig config) {
    return (config.storageId ?? config.chartId ?? config.title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  Future<void> _open(BuildContext context, RateCalculatorConfig config) async {
    String? instanceId;
    if (widget.homeMultiMode) {
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
          homeMultiMode: widget.homeMultiMode,
          availableConfigs: _menuConfigs,
        ),
      ),
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
                  'Rate Calculator',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a tank from the dropdown and open the calculator directly.',
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
      appBar: const AppHeader(title: 'Rate Calculator', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _hero(context),
          _sectionLabel('TANK SELECTOR'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.95),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<RateCalculatorConfig>(
                  initialValue: _selectedConfig,
                  decoration: const InputDecoration(labelText: 'Tank'),
                  items: _menuConfigs
                      .map(
                        (config) => DropdownMenuItem(
                          value: config,
                          child: Text(config.title),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedConfig = value);
                  },
                ),
                if (_selectedConfig.title == 'Production Tank') ...[
                  const SizedBox(height: 12),
                  WwNumberField(
                    label: 'Production Tank Factor (BBL/In)',
                    controller: _productionTankFactorController,
                    helperText:
                        'Default: 1.67. Change this if your production tank factor is different.',
                    allowDecimal: true,
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _open(
                      context,
                      _selectedConfig.title == 'Production Tank'
                          ? _productionTankConfig()
                          : _selectedConfig,
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Open Calculator'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
