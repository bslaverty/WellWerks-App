import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../widgets/app_header.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = AppSettingsService();
  final _bblPerInch = TextEditingController();

  String _gasUnit = 'mcfd';
  String _gaugeType = 'inches';
  String _gasCalculationMethod = 'accumulator';
  String _chokeDisplay = 'ADJ';
  Set<String> _optionalSections =
      Set<String>.from(AppSettingsDefaults.optionalReportSections);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bblPerInch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _service.load();
    if (!mounted) return;
    setState(() {
      _gasUnit = settings.defaultGasUnit;
      _gaugeType = settings.defaultGaugeType;
      _bblPerInch.text = settings.defaultBblPerInch;
      _gasCalculationMethod = settings.defaultGasCalculationMethod;
      _chokeDisplay = settings.defaultChokeDisplay;
      _optionalSections =
          Set<String>.from(settings.defaultOptionalReportSections);
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _service.save(
      AppSettingsData(
        defaultGasUnit: _gasUnit,
        defaultGaugeType: _gaugeType,
        defaultBblPerInch: _bblPerInch.text.trim(),
        defaultGasCalculationMethod: _gasCalculationMethod,
        defaultChokeDisplay: _chokeDisplay,
        defaultOptionalReportSections: AppSettingsDefaults
            .optionalReportSections
            .where(_optionalSections.contains)
            .toList(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );
  }

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required Future<void> Function() action,
    required String success,
  }) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Settings', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Production Defaults',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _gasUnit,
                    decoration: const InputDecoration(labelText: 'Gas Units'),
                    items: const [
                      DropdownMenuItem(value: 'mcfd', child: Text('MCF/D')),
                      DropdownMenuItem(value: 'mmcfd', child: Text('MMCF/D')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _gasUnit = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _gaugeType,
                    decoration:
                        const InputDecoration(labelText: 'Tank Gauge Units'),
                    items: const [
                      DropdownMenuItem(value: 'inches', child: Text('Inches')),
                      DropdownMenuItem(
                          value: 'feetInches', child: Text('Feet + Inches')),
                      DropdownMenuItem(
                          value: 'decimalFeet', child: Text('Decimal Feet')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _gaugeType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _gasCalculationMethod,
                    decoration: const InputDecoration(
                      labelText: 'Default Gas Calculation',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'accumulator',
                        child: Text('Gas Accumulator'),
                      ),
                      DropdownMenuItem(
                        value: 'manual',
                        child: Text('Manual Sales Gas Rate'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _gasCalculationMethod = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _chokeDisplay,
                    decoration: const InputDecoration(
                      labelText: 'Default Choke Display',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ADJ', child: Text('ADJ')),
                      DropdownMenuItem(value: 'POS', child: Text('POS')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _chokeDisplay = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Optional Report Sections',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These defaults are saved app-wide for future production reuse. They do not replace your current Text/Report Layout profiles.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  for (final section
                      in AppSettingsData.optionalReportSectionOptions)
                    SwitchListTile.adaptive(
                      value: _optionalSections.contains(section.id),
                      onChanged: (value) {
                        setState(() {
                          if (value) {
                            _optionalSections.add(section.id);
                          } else {
                            _optionalSections.remove(section.id);
                          }
                        });
                      },
                      title: Text(section.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tank Default',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bblPerInch,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Default BBL/in Factor'),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Data Management',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmAndRun(
                        title: 'Clear Active Data?',
                        body:
                            'This clears the active job, active production shift, and current JSA draft.',
                        action: _service.clearActiveData,
                        success: 'Active local data cleared.',
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear Active Data'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmAndRun(
                        title: 'Clear Archived History?',
                        body:
                            'This removes all archived local history records.',
                        action: _service.clearHistory,
                        success: 'Archived history cleared.',
                      ),
                      icon: const Icon(Icons.history_toggle_off),
                      label: const Text('Clear Archived History'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
