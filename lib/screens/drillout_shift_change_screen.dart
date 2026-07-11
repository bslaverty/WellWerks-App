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
import '../utils/gauge_keypad_input.dart';
import '../utils/gauge_parser.dart';
import '../widgets/app_header.dart';
import '../widgets/choke_selector_sheet.dart';
import '../widgets/shared_gauge_keypad.dart';
import '../widgets/time_wheel_picker_sheet.dart';
import '../widgets/ww_number_field.dart';

enum _DrilloutGaugeTarget { primary, gas1, gas2, water1, water2 }

class DrilloutShiftChangeScreen extends StatefulWidget {
  const DrilloutShiftChangeScreen({super.key});

  @override
  State<DrilloutShiftChangeScreen> createState() =>
      _DrilloutShiftChangeScreenState();
}

class _DrilloutShiftChangeScreenState extends State<DrilloutShiftChangeScreen> {
  static const _prefsBase = 'wellwerks_drillout_shift_change_v1';
  static const _rateLogPrefix = 'wellwerks_rate_log_entries_';
  static const _defaultShiftHour = 5;

  final _jobStorage = JobStorageService();
  final _settingsService = AppSettingsService();

  final _customer = TextEditingController();
  final _wellName = TextEditingController();
  final _rate = TextEditingController();
  final _surfaceTotalFluid = TextEditingController();
  final _waterHauled = TextEditingController();
  final _oilHauled = TextEditingController();

  final _primaryGauge = TextEditingController();
  final _gas1Gauge = TextEditingController();
  final _gas2Gauge = TextEditingController();
  final _water1Gauge = TextEditingController();
  final _water2Gauge = TextEditingController();

  JobSetup? _activeJob;
  String _primaryTank = 'sandx';
  bool _showGasTank = false;
  bool _showGasTank2 = false;
  bool _showWaterTank = false;
  bool _showWaterTank2 = false;
  String _waterTankType = 'flowback_round_bottom';
  String _waterTank2Type = 'flowback_round_bottom';
  _DrilloutGaugeTarget? _activeGaugeTarget;

  ChokeSelection _choke = const ChokeSelection(type: ChokeTypes.none);
  String _textTimeFormat = '12h';
  DateTime _selectedTime = DateTime(2000, 1, 1, _defaultShiftHour);
  String _editedText = '';

  @override
  void initState() {
    super.initState();
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

    final scopedKey = activeJob == null || activeJob.id.trim().isEmpty
        ? _prefsBase
        : '$_prefsBase:${activeJob.id.trim()}';

    final raw = prefs.getString(scopedKey);
    Map<String, dynamic> saved = const <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        saved = Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {
        saved = const <String, dynamic>{};
      }
    }

    final fallbackCustomer = activeJob?.customer.trim().isNotEmpty == true
        ? activeJob!.customer.trim()
        : activeJob?.company.trim() ?? '';
    final fallbackWell = activeJob?.primaryWell.trim() ?? '';

    final customerText = saved.containsKey('customer')
        ? (saved['customer'] as String? ?? '')
        : fallbackCustomer;
    final wellText = saved.containsKey('wellName')
        ? (saved['wellName'] as String? ?? '')
        : fallbackWell;

    final latestRate = _latestBblPerMinuteFromLogs(prefs);

    final savedTypeRaw =
        (saved['chokeType'] as String? ?? '').trim().toUpperCase();
    final savedType = savedTypeRaw == ChokeTypes.adjustable ||
            savedTypeRaw == ChokeTypes.positive ||
            savedTypeRaw == ChokeTypes.none
        ? savedTypeRaw
        : ChokeTypes.none;
    int? savedSize = saved['chokeSize'] as int?;

    // Backward compatibility with prior drillout key.
    savedSize ??= saved['choke64'] as int?;

    final normalizedChoke = savedType == ChokeTypes.none || savedSize == null
        ? const ChokeSelection(type: ChokeTypes.none)
        : ChokeSelection(type: savedType, size64: savedSize.clamp(2, 64));

    final savedHourRaw = saved['selectedHour'];
    final savedHour =
        savedHourRaw is int && savedHourRaw >= 0 && savedHourRaw <= 23
            ? savedHourRaw
            : _defaultShiftHour;

    if (!mounted) return;
    setState(() {
      _activeJob = activeJob;
      _textTimeFormat = settings.textTimeFormat;
      _customer.text = customerText;
      _wellName.text = wellText;
      _primaryTank = _normalizePrimaryTank(saved['primaryTank'] as String?);
      _showGasTank = saved['showGasTank'] as bool? ?? false;
      _showGasTank2 = saved['showGasTank2'] as bool? ?? false;
      _showWaterTank = saved['showWaterTank'] as bool? ?? false;
      _showWaterTank2 = saved['showWaterTank2'] as bool? ?? false;
      _waterTankType =
          _normalizeWaterTankType(saved['waterTankType'] as String?);
      _waterTank2Type =
          _normalizeWaterTankType(saved['waterTank2Type'] as String?);
      _choke = normalizedChoke;
      _selectedTime = DateTime(2000, 1, 1, savedHour);

      if (_rate.text.trim().isEmpty && latestRate != null) {
        _rate.text = _fmtTrim(latestRate);
      }
    });
  }

  Future<void> _saveSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _jobScopedKey,
      jsonEncode({
        'customer': _customer.text.trim(),
        'wellName': _wellName.text.trim(),
        'primaryTank': _primaryTank,
        'showGasTank': _showGasTank,
        'showGasTank2': _showGasTank2,
        'showWaterTank': _showWaterTank,
        'showWaterTank2': _showWaterTank2,
        'waterTankType': _waterTankType,
        'waterTank2Type': _waterTank2Type,
        'selectedHour': _selectedTime.hour,
        'chokeType': _choke.type,
        'chokeSize': _choke.size64,
      }),
    );
  }

  Future<void> _clearSavedSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_jobScopedKey);
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
        // Ignore malformed persisted data.
      }
    }
    return newestRate;
  }

  String _fmtTrim(double value) {
    if (value.isNaN || value.isInfinite) return '0';
    final fixed = value.toStringAsFixed(2);
    return fixed
        .replaceFirst(RegExp(r'\.00$'), '')
        .replaceFirst(RegExp(r'0$'), '');
  }

  String _fmtWholeBbl(String raw) {
    final parsed = double.tryParse(raw.trim()) ?? 0;
    return parsed.round().toString();
  }

  String _formatTime(DateTime value) {
    if (_textTimeFormat == '24h') {
      return DateFormat('HH:mm').format(value);
    }
    return DateFormat('h:mm a').format(value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimeWheelPickerSheet(
      context,
      initialTime: TimeOfDay(hour: _selectedTime.hour, minute: 0),
      use24Hour: _textTimeFormat == '24h',
    );

    if (!mounted || picked == null) return;
    setState(() {
      _selectedTime = DateTime(
        _selectedTime.year,
        _selectedTime.month,
        _selectedTime.day,
        picked.hour,
        0,
      );
    });
    await _saveSetup();
  }

  Future<void> _pickChoke() async {
    final picked = await showChokeSelectorSheet(
      context,
      initial: _choke,
      allowNone: true,
    );
    if (!mounted || picked == null) return;

    setState(() {
      _choke = picked;
    });
    await _saveSetup();
  }

  double? _parseGaugeOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = parseGaugeInput(trimmed);
    if (parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

  String _normalizePrimaryTank(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'fs3':
        return 'fs3';
      case 'flowback500':
        return 'flowback500';
      case 'flowback_round_bottom':
        return 'flowback_round_bottom';
      case 'sand_tank':
      case 'sandx':
      default:
        return 'sandx';
    }
  }

  String _normalizeWaterTankType(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'flowback500':
        return 'flowback500';
      case 'flowback_round_bottom':
      default:
        return 'flowback_round_bottom';
    }
  }

  TankChart _flowbackWaterChart(String typeId) {
    return typeId == 'flowback500'
        ? flowback500Chart
        : flowbackRoundBottomChart;
  }

  String _waterTypeLabel(String typeId) {
    return typeId == 'flowback500'
        ? 'Flowback Tank - V Bottom'
        : 'Flowback Tank - Round Bottom';
  }

  TextEditingController? get _activeGaugeController {
    switch (_activeGaugeTarget) {
      case _DrilloutGaugeTarget.primary:
        return _primaryGauge;
      case _DrilloutGaugeTarget.gas1:
        return _gas1Gauge;
      case _DrilloutGaugeTarget.gas2:
        return _gas2Gauge;
      case _DrilloutGaugeTarget.water1:
        return _water1Gauge;
      case _DrilloutGaugeTarget.water2:
        return _water2Gauge;
      case null:
        return null;
    }
  }

  String get _activeGaugeLabel {
    switch (_activeGaugeTarget) {
      case _DrilloutGaugeTarget.primary:
        return _primaryTankLabel();
      case _DrilloutGaugeTarget.gas1:
        return 'Gas Tank';
      case _DrilloutGaugeTarget.gas2:
        return 'Gas Tank 2';
      case _DrilloutGaugeTarget.water1:
        return 'Water Tank';
      case _DrilloutGaugeTarget.water2:
        return 'Water Tank 2';
      case null:
        return '';
    }
  }

  void _setActiveGauge(_DrilloutGaugeTarget target) {
    FocusScope.of(context).unfocus();
    setState(() => _activeGaugeTarget = target);
  }

  void _insertGaugeText(String raw) {
    final controller = _activeGaugeController;
    if (controller == null) return;
    setState(() {
      controller.value = GaugeKeypadInput.insert(controller.value, raw);
    });
  }

  void _backspaceGauge() {
    final controller = _activeGaugeController;
    if (controller == null || controller.text.isEmpty) return;
    setState(() {
      controller.value = GaugeKeypadInput.backspace(controller.value);
    });
  }

  void _clearActiveGauge() {
    final controller = _activeGaugeController;
    if (controller == null) return;
    setState(controller.clear);
  }

  void _closeGaugeKeypad() {
    setState(() => _activeGaugeTarget = null);
  }

  TankChart _primaryChart() {
    switch (_primaryTank) {
      case 'fs3':
        return fs3Chart;
      case 'flowback500':
        return flowback500Chart;
      case 'flowback_round_bottom':
        return flowbackRoundBottomChart;
      case 'sandx':
      default:
        return sandXChart;
    }
  }

  String _primaryTankLabel() {
    switch (_primaryTank) {
      case 'fs3':
        return 'FS3';
      case 'flowback500':
        return 'Flowback Tank - V Bottom';
      case 'flowback_round_bottom':
        return 'Flowback Tank - Round Bottom';
      case 'sandx':
      default:
        return 'SandX';
    }
  }

  String _inventoryLine(String label, double? gauge, TankChart chart) {
    if (gauge == null) {
      return '$label: — / — bbl';
    }
    return '$label: ${_fmtTrim(gauge)}" / ${chart.barrelsAt(gauge).round()} bbl';
  }

  String _composeText() {
    final primaryGauge = _parseGaugeOrNull(_primaryGauge.text);

    final lines = <String>[
      'DRILLOUT SHIFT CHANGE',
      '',
      _customer.text.trim(),
      _wellName.text.trim(),
      _formatTime(_selectedTime),
      '',
      if (!_choke.isNone) 'Choke: ${formatChokeDisplay(_choke)}',
      'Rate: ${_fmtTrim(double.tryParse(_rate.text.trim()) ?? 0)} bbl/min',
      '',
      'Surface Total Fluid: ${_fmtWholeBbl(_surfaceTotalFluid.text)} bbl',
      'Water Hauled: ${_fmtWholeBbl(_waterHauled.text)} bbl',
      'Oil Hauled: ${_fmtWholeBbl(_oilHauled.text)} bbl',
      '',
      'Tank Inventory',
      '',
      _inventoryLine(_primaryTankLabel(), primaryGauge, _primaryChart()),
    ];

    if (_showGasTank) {
      final gauge = _parseGaugeOrNull(_gas1Gauge.text);
      lines.add(_inventoryLine('Gas Tank', gauge, flowbackGasTankChart));
    }
    if (_showGasTank2) {
      final gauge = _parseGaugeOrNull(_gas2Gauge.text);
      lines.add(_inventoryLine('Gas Tank 2', gauge, flowbackGasTankChart));
    }
    if (_showWaterTank) {
      final gauge = _parseGaugeOrNull(_water1Gauge.text);
      lines.add(_inventoryLine(
          'Water Tank', gauge, _flowbackWaterChart(_waterTankType)));
    }
    if (_showWaterTank2) {
      final gauge = _parseGaugeOrNull(_water2Gauge.text);
      lines.add(_inventoryLine(
          'Water Tank 2', gauge, _flowbackWaterChart(_waterTank2Type)));
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

  Future<void> _clearCurrentShiftValues() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Current Shift Values?'),
            content: const Text(
              'This clears current shift values only and keeps Drillout setup information.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Current Values'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _selectedTime = DateTime(2000, 1, 1, _defaultShiftHour);
      _rate.clear();
      _surfaceTotalFluid.clear();
      _waterHauled.clear();
      _oilHauled.clear();
      _primaryGauge.clear();
      _gas1Gauge.clear();
      _gas2Gauge.clear();
      _water1Gauge.clear();
      _water2Gauge.clear();
      _editedText = '';
      _activeGaugeTarget = null;
    });
    await _saveSetup();
  }

  Future<void> _clearDrilloutSetup() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Drillout Setup?'),
            content: const Text(
              'This will remove Company/Customer, Well Name, primary tank selection, optional tank configuration, selected choke, and saved Drillout layout for this active setup.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Drillout Setup'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _customer.clear();
      _wellName.clear();
      _primaryTank = 'sandx';
      _showGasTank = false;
      _showGasTank2 = false;
      _showWaterTank = false;
      _showWaterTank2 = false;
      _waterTankType = 'flowback_round_bottom';
      _waterTank2Type = 'flowback_round_bottom';
      _choke = const ChokeSelection(type: ChokeTypes.none);
      _selectedTime = DateTime(2000, 1, 1, _defaultShiftHour);
      _rate.clear();
      _surfaceTotalFluid.clear();
      _waterHauled.clear();
      _oilHauled.clear();
      _primaryGauge.clear();
      _gas1Gauge.clear();
      _gas2Gauge.clear();
      _water1Gauge.clear();
      _water2Gauge.clear();
      _editedText = '';
      _activeGaugeTarget = null;
    });

    await _clearSavedSetup();
    await _saveSetup();
  }

  Widget _gaugeCard({
    required String title,
    required TankChart chart,
    required TextEditingController controller,
    required _DrilloutGaugeTarget target,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final gauge = _parseGaugeOrNull(controller.text);
    final gaugeText = gauge == null ? '—' : '${_fmtTrim(gauge)}"';
    final barrelText =
        gauge == null ? '—' : '${_fmtTrim(chart.barrelsAt(gauge))} bbl';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            WwGaugeField(
              label: 'Gauge',
              controller: controller,
              hintText: '30.25',
              active: _activeGaugeTarget == target,
              onTap: () => _setActiveGauge(target),
              onChanged: (_) => setState(() {}),
            ),
            Text(
              'Gauge: $gaugeText   •   Barrels: $barrelText',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _customer.dispose();
    _wellName.dispose();
    _rate.dispose();
    _surfaceTotalFluid.dispose();
    _waterHauled.dispose();
    _oilHauled.dispose();
    _primaryGauge.dispose();
    _gas1Gauge.dispose();
    _gas2Gauge.dispose();
    _water1Gauge.dispose();
    _water2Gauge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Drillout Shift Change', showBack: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
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
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 20),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _customer,
                          onChanged: (_) => _saveSetup(),
                          decoration: const InputDecoration(
                              labelText: 'Company / Customer'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _wellName,
                          onChanged: (_) => _saveSetup(),
                          decoration:
                              const InputDecoration(labelText: 'Well Name'),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule),
                          title: const Text('Shift Change Time'),
                          subtitle: Text(_formatTime(_selectedTime)),
                          trailing: FilledButton(
                            onPressed: _pickTime,
                            child: const Text('Select'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.tune),
                          title: const Text('Choke Selector'),
                          subtitle: Text(formatChokeDisplay(_choke)),
                          trailing: FilledButton(
                            onPressed: _pickChoke,
                            child: const Text('Select'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _rate,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Rate Override (bbl/min)'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _surfaceTotalFluid,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Surface Total Fluid (bbl)'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _waterHauled,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Water Hauled (bbl)'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _oilHauled,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Oil Hauled (bbl)'),
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
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _primaryTank,
                          decoration: const InputDecoration(
                            labelText: 'Primary Drillout Tank',
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'sandx', child: Text('SandX')),
                            DropdownMenuItem(value: 'fs3', child: Text('FS3')),
                            DropdownMenuItem(
                                value: 'flowback500',
                                child: Text('Flowback Tank - V Bottom')),
                            DropdownMenuItem(
                                value: 'flowback_round_bottom',
                                child: Text('Flowback Tank - Round Bottom')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _primaryTank = value);
                            _saveSetup();
                          },
                        ),
                        const SizedBox(height: 10),
                        _gaugeCard(
                          title: _primaryTankLabel(),
                          chart: _primaryChart(),
                          controller: _primaryGauge,
                          target: _DrilloutGaugeTarget.primary,
                        ),
                        SwitchListTile.adaptive(
                          value: _showGasTank,
                          onChanged: (value) {
                            setState(() => _showGasTank = value);
                            _saveSetup();
                          },
                          title: const Text('Gas Tank'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_showGasTank)
                          _gaugeCard(
                            title: 'Gas Tank',
                            chart: flowbackGasTankChart,
                            controller: _gas1Gauge,
                            target: _DrilloutGaugeTarget.gas1,
                          ),
                        SwitchListTile.adaptive(
                          value: _showGasTank2,
                          onChanged: (value) {
                            setState(() => _showGasTank2 = value);
                            _saveSetup();
                          },
                          title: const Text('Gas Tank 2'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_showGasTank2)
                          _gaugeCard(
                            title: 'Gas Tank 2',
                            chart: flowbackGasTankChart,
                            controller: _gas2Gauge,
                            target: _DrilloutGaugeTarget.gas2,
                          ),
                        SwitchListTile.adaptive(
                          value: _showWaterTank,
                          onChanged: (value) {
                            setState(() => _showWaterTank = value);
                            _saveSetup();
                          },
                          title: const Text('Water Tank'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_showWaterTank)
                          Column(
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: _waterTankType,
                                decoration: const InputDecoration(
                                  labelText: 'Water Tank Type',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'flowback500',
                                      child: Text('Flowback Tank - V Bottom')),
                                  DropdownMenuItem(
                                      value: 'flowback_round_bottom',
                                      child:
                                          Text('Flowback Tank - Round Bottom')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _waterTankType = value);
                                  _saveSetup();
                                },
                              ),
                              const SizedBox(height: 8),
                              _gaugeCard(
                                title:
                                    'Water Tank (${_waterTypeLabel(_waterTankType)})',
                                chart: _flowbackWaterChart(_waterTankType),
                                controller: _water1Gauge,
                                target: _DrilloutGaugeTarget.water1,
                              ),
                            ],
                          ),
                        SwitchListTile.adaptive(
                          value: _showWaterTank2,
                          onChanged: (value) {
                            setState(() => _showWaterTank2 = value);
                            _saveSetup();
                          },
                          title: const Text('Water Tank 2'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_showWaterTank2)
                          Column(
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: _waterTank2Type,
                                decoration: const InputDecoration(
                                  labelText: 'Water Tank 2 Type',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'flowback500',
                                      child: Text('Flowback Tank - V Bottom')),
                                  DropdownMenuItem(
                                      value: 'flowback_round_bottom',
                                      child:
                                          Text('Flowback Tank - Round Bottom')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _waterTank2Type = value);
                                  _saveSetup();
                                },
                              ),
                              const SizedBox(height: 8),
                              _gaugeCard(
                                title:
                                    'Water Tank 2 (${_waterTypeLabel(_waterTank2Type)})',
                                chart: _flowbackWaterChart(_waterTank2Type),
                                controller: _water2Gauge,
                                target: _DrilloutGaugeTarget.water2,
                              ),
                            ],
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
                      onPressed: _clearCurrentShiftValues,
                      icon: const Icon(Icons.layers_clear),
                      label: const Text('Clear Current Shift Values'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearDrilloutSetup,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Clear Drillout Setup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_activeGaugeTarget != null)
            SharedGaugeKeypad(
              activeFieldLabel: _activeGaugeLabel,
              onInsert: _insertGaugeText,
              onBackspace: _backspaceGauge,
              onClear: _clearActiveGauge,
              onDone: _closeGaugeKeypad,
            ),
        ],
      ),
    );
  }
}
