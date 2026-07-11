import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tank_charts.dart';
import '../models/job_setup.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../widgets/app_header.dart';
import '../widgets/tank_gauge_entry_card.dart';

class DrilloutShiftChangeScreen extends StatefulWidget {
  const DrilloutShiftChangeScreen({super.key});

  @override
  State<DrilloutShiftChangeScreen> createState() =>
      _DrilloutShiftChangeScreenState();
}

class _DrilloutShiftChangeScreenState extends State<DrilloutShiftChangeScreen> {
  static const _prefsBase = 'wellwerks_drillout_shift_change_v1';
  static const _rateLogPrefix = 'wellwerks_rate_log_entries_';

  final _jobStorage = JobStorageService();
  final _settingsService = AppSettingsService();

  final _customer = TextEditingController();
  final _wellName = TextEditingController();
  final _time = TextEditingController();
  final _rate = TextEditingController();
  final _surfaceTotalFluid = TextEditingController();
  final _waterHauled = TextEditingController();
  final _oilHauled = TextEditingController();

  final _primaryWhole = TextEditingController();
  final _primaryFrac = TextEditingController();
  final _gas1Whole = TextEditingController();
  final _gas1Frac = TextEditingController();
  final _gas2Whole = TextEditingController();
  final _gas2Frac = TextEditingController();
  final _water1Whole = TextEditingController();
  final _water1Frac = TextEditingController();
  final _water2Whole = TextEditingController();
  final _water2Frac = TextEditingController();

  JobSetup? _activeJob;
  String _primaryTank = 'sandx';
  bool _showGasTank = false;
  bool _showGasTank2 = false;
  bool _showWaterTank = false;
  bool _showWaterTank2 = false;
  int? _selectedChoke64;
  String _textTimeFormat = '12h';
  DateTime _selectedTime = DateTime.now();
  String _editedText = '';

  @override
  void initState() {
    super.initState();
    _selectedTime = DateTime.now();
    _time.text = _formatSelectedTime(_selectedTime);
    _load();
  }

  String get _jobScopedKey {
    final jobId = (_activeJob?.id ?? '').trim();
    if (jobId.isEmpty) return _prefsBase;
    return '$_prefsBase:$jobId';
  }

  Future<void> _load() async {
    final activeJob = await _jobStorage.loadActiveJob();
    final settings = await _settingsService.load();
    final prefs = await SharedPreferences.getInstance();
    final jobScopedKey = activeJob == null || activeJob.id.trim().isEmpty
        ? _prefsBase
        : '$_prefsBase:${activeJob.id.trim()}';

    final raw = prefs.getString(jobScopedKey);
    Map<String, dynamic> saved = const <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        saved = Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {
        saved = const <String, dynamic>{};
      }
    }

    if (!mounted) return;
    setState(() {
      _activeJob = activeJob;
      _textTimeFormat = settings.textTimeFormat;
      _customer.text = activeJob?.customer.trim().isNotEmpty == true
          ? activeJob!.customer.trim()
          : activeJob?.company.trim() ?? '';
      _wellName.text = activeJob?.primaryWell.trim() ?? '';

      _primaryTank = (saved['primaryTank'] as String? ?? 'sandx').trim();
      _showGasTank = saved['showGasTank'] as bool? ?? false;
      _showGasTank2 = saved['showGasTank2'] as bool? ?? false;
      _showWaterTank = saved['showWaterTank'] as bool? ?? false;
      _showWaterTank2 = saved['showWaterTank2'] as bool? ?? false;
      final chokeValue = saved['choke64'];
      if (chokeValue is int && chokeValue >= 2 && chokeValue <= 64) {
        _selectedChoke64 = chokeValue;
      }

      final latestRate = _latestBblPerMinuteFromLogs(prefs);
      if (latestRate != null) {
        _rate.text = _fmtTrim(latestRate);
      }

      _time.text = _formatSelectedTime(_selectedTime);
    });
  }

  Future<void> _saveTankVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _jobScopedKey,
      jsonEncode({
        'primaryTank': _primaryTank,
        'showGasTank': _showGasTank,
        'showGasTank2': _showGasTank2,
        'showWaterTank': _showWaterTank,
        'showWaterTank2': _showWaterTank2,
        'choke64': _selectedChoke64,
      }),
    );
  }

  double? _latestBblPerMinuteFromLogs(SharedPreferences prefs) {
    DateTime? newest;
    double? newestRate;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_rateLogPrefix)) continue;
      final rawEntries = prefs.getString(key);
      if (rawEntries == null || rawEntries.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(rawEntries);
        if (decoded is! List) continue;
        for (final item in decoded) {
          if (item is! Map) continue;
          final timestampMs = item['timestampMs'];
          final rateValue = item['rateValue'];
          final rateUnit = (item['rateUnit'] as String? ?? '').toLowerCase();
          if (timestampMs is! int || rateValue is! num || rateUnit.isEmpty) {
            continue;
          }
          final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
          final asBblPerMin = rateUnit.contains('/hr')
              ? rateValue.toDouble() / 60
              : rateValue.toDouble();
          if (newest == null || timestamp.isAfter(newest)) {
            newest = timestamp;
            newestRate = asBblPerMin;
          }
        }
      } catch (_) {
        // Ignore malformed persisted log data from older builds.
      }
    }
    return newestRate;
  }

  String _fmtTrim(double value) {
    if (value.isNaN || value.isInfinite) return '0';
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.00$'), '').replaceFirst(RegExp(r'0$'), '');
  }

  String _fmtWholeBbl(String raw) {
    final parsed = double.tryParse(raw.trim()) ?? 0;
    return parsed.round().toString();
  }

  String _formatSelectedTime(DateTime value) {
    if (_textTimeFormat == '24h') {
      return DateFormat('HH:mm').format(value);
    }
    return DateFormat('h:mm a').format(value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: _selectedTime.hour, minute: _selectedTime.minute),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedTime = DateTime(
        _selectedTime.year,
        _selectedTime.month,
        _selectedTime.day,
        picked.hour,
        picked.minute,
      );
      _time.text = _formatSelectedTime(_selectedTime);
    });
  }

  double _parseGauge(String wholeRaw, String fractionRaw) {
    final whole = double.tryParse(wholeRaw.trim()) ?? 0;
    final raw = fractionRaw.trim();
    if (raw.isEmpty) return whole;
    if (raw.contains('/')) {
      final parts = raw.split('/');
      if (parts.length == 2) {
        final top = double.tryParse(parts.first.trim()) ?? 0;
        final bottom = double.tryParse(parts.last.trim()) ?? 1;
        if (bottom != 0) {
          return whole + (top / bottom);
        }
      }
    }
    final decimal = double.tryParse(raw) ?? 0;
    return whole + decimal;
  }

  TankChart _primaryChart() {
    switch (_primaryTank) {
      case 'fs3':
        return fs3Chart;
      case 'sand_tank':
        return sandXChart;
      case 'sandx':
      default:
        return sandXChart;
    }
  }

  String _primaryTankLabel() {
    switch (_primaryTank) {
      case 'fs3':
        return 'FS3';
      case 'sand_tank':
        return 'Sand Tank';
      case 'sandx':
      default:
        return 'SandX';
    }
  }

  String _formatChoke() {
    if (_selectedChoke64 == null) return '--';
    return '$_selectedChoke64/64"';
  }

  String _inventoryLine(String label, double gauge, double bbl) {
    final gaugeText = '${_fmtTrim(gauge)}"';
    return '$label: $gaugeText / ${bbl.round()} bbl';
  }

  String _composeText() {
    final primaryGauge = _parseGauge(_primaryWhole.text, _primaryFrac.text);
    final primaryBbl = _primaryChart().barrelsAt(primaryGauge);

    final lines = <String>[
      'DRILLOUT SHIFT CHANGE',
      '',
      _customer.text.trim(),
      _wellName.text.trim(),
      _formatSelectedTime(_selectedTime),
      '',
      'Choke: ${_formatChoke()}',
      'Rate: ${_fmtTrim(double.tryParse(_rate.text.trim()) ?? 0)} bbl/min',
      '',
      'Surface Total Fluid: ${_fmtWholeBbl(_surfaceTotalFluid.text)} bbl',
      'Water Hauled: ${_fmtWholeBbl(_waterHauled.text)} bbl',
      'Oil Hauled: ${_fmtWholeBbl(_oilHauled.text)} bbl',
      '',
      'Tank Inventory',
      '',
      _inventoryLine(_primaryTankLabel(), primaryGauge, primaryBbl),
    ];

    if (_showGasTank) {
      final gauge = _parseGauge(_gas1Whole.text, _gas1Frac.text);
      lines.add(_inventoryLine(
          'Gas Tank', gauge, flowbackGasTankChart.barrelsAt(gauge)));
    }
    if (_showGasTank2) {
      final gauge = _parseGauge(_gas2Whole.text, _gas2Frac.text);
      lines.add(_inventoryLine(
          'Gas Tank 2', gauge, flowbackGasTankChart.barrelsAt(gauge)));
    }
    if (_showWaterTank) {
      final gauge = _parseGauge(_water1Whole.text, _water1Frac.text);
      lines.add(_inventoryLine(
          'Water Tank', gauge, flowbackRoundBottomChart.barrelsAt(gauge)));
    }
    if (_showWaterTank2) {
      final gauge = _parseGauge(_water2Whole.text, _water2Frac.text);
      lines.add(_inventoryLine(
          'Water Tank 2', gauge, flowbackRoundBottomChart.barrelsAt(gauge)));
    }

    return lines
        .where((line) => line.trim().isNotEmpty || line.isEmpty)
        .join('\n');
  }

  Future<void> _preview() async {
    final text = _editedText.trim().isNotEmpty ? _editedText : _composeText();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview'),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final controller = TextEditingController(
      text: _editedText.trim().isNotEmpty ? _editedText : _composeText(),
    );
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Shift Change Text'),
        content: TextField(
          controller: controller,
          maxLines: 16,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use Edited Text'),
          ),
        ],
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => _editedText = saved);
  }

  Future<void> _copy() async {
    final text = _editedText.trim().isNotEmpty ? _editedText : _composeText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shift change copied to clipboard.')),
    );
  }

  Future<void> _share() async {
    final text = _editedText.trim().isNotEmpty ? _editedText : _composeText();
    await Share.share(text, subject: 'DRILLOUT SHIFT CHANGE');
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Current Shift Entry?'),
            content: const Text(
              'This clears current shift values only and keeps Drillout Job Setup.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _selectedChoke64 = null;
      _rate.clear();
      _surfaceTotalFluid.clear();
      _waterHauled.clear();
      _oilHauled.clear();
      _primaryWhole.clear();
      _primaryFrac.clear();
      _gas1Whole.clear();
      _gas1Frac.clear();
      _gas2Whole.clear();
      _gas2Frac.clear();
      _water1Whole.clear();
      _water1Frac.clear();
      _water2Whole.clear();
      _water2Frac.clear();
      _selectedTime = DateTime.now();
      _time.text = _formatSelectedTime(_selectedTime);
      _editedText = '';
    });
    _saveTankVisibility();
  }

  @override
  void dispose() {
    _customer.dispose();
    _wellName.dispose();
    _time.dispose();
    _rate.dispose();
    _surfaceTotalFluid.dispose();
    _waterHauled.dispose();
    _oilHauled.dispose();
    _primaryWhole.dispose();
    _primaryFrac.dispose();
    _gas1Whole.dispose();
    _gas1Frac.dispose();
    _gas2Whole.dispose();
    _gas2Frac.dispose();
    _water1Whole.dispose();
    _water1Frac.dispose();
    _water2Whole.dispose();
    _water2Frac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Drillout Shift Change', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DRILLOUT SHIFT CHANGE',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _customer,
                      decoration: const InputDecoration(labelText: 'Customer')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _wellName,
                      decoration:
                          const InputDecoration(labelText: 'Well Name')),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: const Text('Shift Change Time'),
                    subtitle: Text(_time.text),
                    trailing: const Icon(Icons.edit),
                    onTap: _pickTime,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedChoke64,
                    decoration: const InputDecoration(
                      labelText: 'Choke',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('None'),
                      ),
                      ...List<DropdownMenuItem<int?>>.generate(
                        32,
                        (index) {
                          final choke = (index + 1) * 2;
                          return DropdownMenuItem<int?>(
                            value: choke,
                            child: Text('$choke/64"'),
                          );
                        },
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedChoke64 = value);
                      _saveTankVisibility();
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _rate,
                      decoration: const InputDecoration(labelText: 'Rate')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _surfaceTotalFluid,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Surface Total Fluid (bbl)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _waterHauled,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Water Hauled (bbl)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _oilHauled,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Oil Hauled (bbl)'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tank Inventory',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _primaryTank,
                    decoration: const InputDecoration(
                      labelText: 'Primary Drillout Tank',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'sandx', child: Text('SandX')),
                      DropdownMenuItem(value: 'fs3', child: Text('FS3')),
                      DropdownMenuItem(
                          value: 'sand_tank', child: Text('Sand Tank')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _primaryTank = value);
                      _saveTankVisibility();
                    },
                  ),
                  const SizedBox(height: 10),
                  TankGaugeEntryCard(
                    title: _primaryTankLabel(),
                    chart: _primaryChart(),
                    wholeInchesController: _primaryWhole,
                    fractionOrDecimalController: _primaryFrac,
                    onChanged: () => setState(() {}),
                  ),
                  SwitchListTile.adaptive(
                    value: _showGasTank,
                    onChanged: (value) {
                      setState(() => _showGasTank = value);
                      _saveTankVisibility();
                    },
                    title: const Text('Gas Tank'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_showGasTank)
                    TankGaugeEntryCard(
                      title: 'Gas Tank',
                      chart: flowbackGasTankChart,
                      wholeInchesController: _gas1Whole,
                      fractionOrDecimalController: _gas1Frac,
                      onChanged: () => setState(() {}),
                    ),
                  SwitchListTile.adaptive(
                    value: _showGasTank2,
                    onChanged: (value) {
                      setState(() => _showGasTank2 = value);
                      _saveTankVisibility();
                    },
                    title: const Text('Gas Tank 2'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_showGasTank2)
                    TankGaugeEntryCard(
                      title: 'Gas Tank 2',
                      chart: flowbackGasTankChart,
                      wholeInchesController: _gas2Whole,
                      fractionOrDecimalController: _gas2Frac,
                      onChanged: () => setState(() {}),
                    ),
                  SwitchListTile.adaptive(
                    value: _showWaterTank,
                    onChanged: (value) {
                      setState(() => _showWaterTank = value);
                      _saveTankVisibility();
                    },
                    title: const Text('Water Tank'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_showWaterTank)
                    TankGaugeEntryCard(
                      title: 'Water Tank',
                      chart: flowbackRoundBottomChart,
                      wholeInchesController: _water1Whole,
                      fractionOrDecimalController: _water1Frac,
                      onChanged: () => setState(() {}),
                    ),
                  SwitchListTile.adaptive(
                    value: _showWaterTank2,
                    onChanged: (value) {
                      setState(() => _showWaterTank2 = value);
                      _saveTankVisibility();
                    },
                    title: const Text('Water Tank 2'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_showWaterTank2)
                    TankGaugeEntryCard(
                      title: 'Water Tank 2',
                      chart: flowbackRoundBottomChart,
                      wholeInchesController: _water2Whole,
                      fractionOrDecimalController: _water2Frac,
                      onChanged: () => setState(() {}),
                    ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _preview,
                icon: const Icon(Icons.preview),
                label: const Text('Preview'),
              ),
              OutlinedButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              OutlinedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Shift Change'),
              ),
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
              ),
              OutlinedButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
