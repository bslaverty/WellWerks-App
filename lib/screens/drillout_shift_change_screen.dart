import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tank_charts.dart';
import '../models/job_setup.dart';
import '../services/active_company_service.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/app_settings_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../utils/gauge_keypad_input.dart';
import '../utils/gauge_parser.dart';
import '../widgets/app_header.dart';
import '../widgets/choke_selector_sheet.dart';
import '../widgets/shared_gauge_keypad.dart';
import '../widgets/time_wheel_picker_sheet.dart';
import '../widgets/ww_number_field.dart';

enum _DrilloutGaugeTarget { primary, gas1, gas2, water1, water2 }

enum _DrilloutMode { shiftChange, update }

class DrilloutShiftChangeScreen extends StatefulWidget {
  const DrilloutShiftChangeScreen({
    super.key,
    this.initialWorkflow,
  });

  final ActiveWorkflowMode? initialWorkflow;

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
  final _activeCompanyService = ActiveCompanyService.instance;
  final _workflowModeService = ActiveWorkflowModeService.instance;

  final _customer = TextEditingController();
  final _wellName = TextEditingController();
  final _rate = TextEditingController();
  final _surfaceTotalFluid = TextEditingController();
  final _waterHauled = TextEditingController();
  final _oilHauled = TextEditingController();
  final _manifoldPsi = TextEditingController();
  final _casingPsi = TextEditingController();
  final _pumpPsi = TextEditingController();
  final _plugNumber = TextEditingController();
  final _coilDepth = TextEditingController();
  final _notes = TextEditingController();

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
  _DrilloutMode _mode = _DrilloutMode.shiftChange;
  ActiveWorkflowMode _workflow = ActiveWorkflowMode.drillout;

  bool _includeRateOverride = false;
  bool _includeSurfaceTotalFluid = false;
  bool _includeWaterHauled = false;
  bool _includeOilHauled = false;
  bool _includeManifoldPsi = false;
  bool _includeCasingPsi = false;
  bool _includePumpPsi = false;

  bool _showStatus = false;
  bool _showPlugNumber = false;
  bool _showCoilDepth = false;
  bool _showGas = false;
  bool _showSand = false;

  double? _latestCalculatedRate;

  String? _status;
  String? _gas;
  String? _sand;

  static const List<String> _statusOptions = [
    'Ready for Pressure Test',
    'Drilling Plugs',
    'Circulating',
    'Equipment Issues',
    'POOH',
  ];

  static const List<String> _sandOptions = [
    'Trace',
    'Light',
    'Medium',
    'Heavy',
  ];

  static const List<String> _gasOptions = [
    'None',
    'Light',
    'Medium',
    'Heavy',
  ];

  @override
  void initState() {
    super.initState();
    _activeCompanyService.activeCompany
        .addListener(_handleActiveCompanyChanged);
    _load();
  }

  Future<void> _handleActiveCompanyChanged() async {
    if (!mounted) return;
    await _load();
  }

  String get _jobScopedKey {
    final jobId = (_activeJob?.id ?? '').trim();
    if (jobId.isEmpty) return _prefsBase;
    return '$_prefsBase:$jobId';
  }

  Future<void> _load() async {
    final activeJob = await _jobStorage.loadActiveJob();
    final settings = await _settingsService.load();
    final activeCompany = await _activeCompanyService.ensureLoaded();
    final savedWorkflow =
        widget.initialWorkflow ?? await _workflowModeService.ensureLoaded();
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

    final fallbackCustomer =
        activeCompany == JobProfileDefaultsService.companyNone
            ? ''
            : activeCompany;
    final fallbackWell = activeJob?.primaryWell.trim() ?? '';

    final customerText = saved.containsKey('customer')
        ? (saved['customer'] as String? ?? '')
        : fallbackCustomer;
    final wellText = saved.containsKey('wellName')
        ? (saved['wellName'] as String? ?? '')
        : fallbackWell;

    final latestRate = _latestBblPerMinuteFromLogs(prefs);
    final savedRateOverride =
        (saved['rateOverride'] as String? ?? saved['rate'] as String? ?? '')
            .trim();
    final savedSurfaceTotalFluid =
        (saved['surfaceTotalFluid'] as String? ?? '').trim();
    final savedWaterHauled = (saved['waterHauled'] as String? ?? '').trim();
    final savedOilHauled = (saved['oilHauled'] as String? ?? '').trim();
    final savedManifoldPsi = (saved['manifoldPsi'] as String? ?? '').trim();
    final savedCasingPsi = (saved['casingPsi'] as String? ?? '').trim();
    final savedPumpPsi = (saved['pumpPsi'] as String? ?? '').trim();

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
      _workflow = savedWorkflow == ActiveWorkflowMode.cleanout
          ? ActiveWorkflowMode.cleanout
          : ActiveWorkflowMode.drillout;
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
      _mode = _modeFromStorage(saved['mode'] as String?);
      _includeRateOverride = _resolveIncludeToggle(
        saved: saved,
        key: 'includeRateOverride',
        value: savedRateOverride,
      );
      _includeSurfaceTotalFluid = _resolveIncludeToggle(
        saved: saved,
        key: 'includeSurfaceTotalFluid',
        value: savedSurfaceTotalFluid,
      );
      _includeWaterHauled = _resolveIncludeToggle(
        saved: saved,
        key: 'includeWaterHauled',
        value: savedWaterHauled,
      );
      _includeOilHauled = _resolveIncludeToggle(
        saved: saved,
        key: 'includeOilHauled',
        value: savedOilHauled,
      );
      _includeManifoldPsi = _resolveIncludeToggle(
        saved: saved,
        key: 'includeManifoldPsi',
        value: savedManifoldPsi,
      );
      _includeCasingPsi = _resolveIncludeToggle(
        saved: saved,
        key: 'includeCasingPsi',
        value: savedCasingPsi,
      );
      _includePumpPsi = _resolveIncludeToggle(
        saved: saved,
        key: 'includePumpPsi',
        value: savedPumpPsi,
      );
      _showStatus = saved.containsKey('showStatus')
          ? (saved['showStatus'] as bool? ?? false)
          : ((saved['status'] as String? ?? '').trim().isNotEmpty);
      _showPlugNumber = saved.containsKey('showPlugNumber')
          ? (saved['showPlugNumber'] as bool? ?? false)
          : ((saved['plugNumber'] as String? ?? '').trim().isNotEmpty);
      _showCoilDepth = saved.containsKey('showCoilDepth')
          ? (saved['showCoilDepth'] as bool? ?? false)
          : ((saved['coilDepth'] as String? ?? '').trim().isNotEmpty);
      _showGas = saved['showGas'] as bool? ??
          saved['showGasSpotRate'] as bool? ??
          false;
      _showSand = saved['showSand'] as bool? ?? false;
      _status = _validatedStatus(saved['status'] as String?);
      _gas = _validatedGas(
        saved['gas'] as String? ?? saved['gasSpotRate'] as String?,
      );
      _sand = _validatedSand(saved['sand'] as String?);
      _rate.text = savedRateOverride;
      _surfaceTotalFluid.text = savedSurfaceTotalFluid;
      _waterHauled.text = savedWaterHauled;
      _oilHauled.text = savedOilHauled;
      _manifoldPsi.text = savedManifoldPsi;
      _casingPsi.text = savedCasingPsi;
      _pumpPsi.text = savedPumpPsi;
      _plugNumber.text = saved['plugNumber'] as String? ?? '';
      _coilDepth.text = saved['coilDepth'] as String? ?? '';
      _notes.text = saved['notes'] as String? ?? '';
      _latestCalculatedRate = latestRate;

      if (_rate.text.trim().isEmpty && latestRate != null) {
        _rate.text = _fmtTrim(latestRate);
      }
    });
  }

  bool _resolveIncludeToggle({
    required Map<String, dynamic> saved,
    required String key,
    required String value,
  }) {
    if (saved.containsKey(key)) {
      return saved[key] as bool? ?? false;
    }
    return value.trim().isNotEmpty;
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
        'mode': _modeStorageValue,
        'chokeType': _choke.type,
        'chokeSize': _choke.size64,
        'includeRateOverride': _includeRateOverride,
        'includeSurfaceTotalFluid': _includeSurfaceTotalFluid,
        'includeWaterHauled': _includeWaterHauled,
        'includeOilHauled': _includeOilHauled,
        'includeManifoldPsi': _includeManifoldPsi,
        'includeCasingPsi': _includeCasingPsi,
        'includePumpPsi': _includePumpPsi,
        'showStatus': _showStatus,
        'showPlugNumber': _showPlugNumber,
        'showCoilDepth': _showCoilDepth,
        'showGas': _showGas,
        'showSand': _showSand,
        'rateOverride': _rate.text.trim(),
        'surfaceTotalFluid': _surfaceTotalFluid.text.trim(),
        'waterHauled': _waterHauled.text.trim(),
        'oilHauled': _oilHauled.text.trim(),
        'manifoldPsi': _manifoldPsi.text.trim(),
        'casingPsi': _casingPsi.text.trim(),
        'pumpPsi': _pumpPsi.text.trim(),
        'status': _status,
        'plugNumber': _plugNumber.text.trim(),
        'coilDepth': _coilDepth.text.trim(),
        'gas': _gas,
        'sand': _sand,
        'notes': _notes.text.trim(),
      }),
    );
  }

  String? _validatedStatus(String? value) {
    final normalized = (value ?? '').trim();
    return _statusOptions.contains(normalized) ? normalized : null;
  }

  String? _validatedSand(String? value) {
    final normalized = (value ?? '').trim();
    return _sandOptions.contains(normalized) ? normalized : null;
  }

  String? _validatedGas(String? value) {
    final normalized = (value ?? '').trim();
    return _gasOptions.contains(normalized) ? normalized : null;
  }

  _DrilloutMode _modeFromStorage(String? value) {
    return (value ?? '').trim().toLowerCase() == 'update'
        ? _DrilloutMode.update
        : _DrilloutMode.shiftChange;
  }

  String get _modeStorageValue =>
      _mode == _DrilloutMode.update ? 'update' : 'shift_change';

  String get _modeLabel =>
      _mode == _DrilloutMode.update ? 'Update' : 'Shift Change';

  String get _workflowLabel =>
      _workflow == ActiveWorkflowMode.cleanout ? 'Cleanout' : 'Drillout';

  String get _workflowTitle => '$_workflowLabel Shift Change / Update';

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

  bool _hasEnteredValue(String raw) {
    return raw.trim().isNotEmpty;
  }

  double _resolvedRateBblPerMin() {
    final override = double.tryParse(_rate.text.trim());
    if (_includeRateOverride && override != null) {
      return override;
    }
    return _latestCalculatedRate ?? override ?? 0;
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

  void _onOptionalToggleChanged({
    required bool nextValue,
    required void Function(bool) assign,
  }) {
    if (!nextValue) {
      FocusScope.of(context).unfocus();
    }
    setState(() => assign(nextValue));
    _saveSetup();
  }

  Widget _optionalToggleRow({
    required Key key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Switch.adaptive(key: key, value: value, onChanged: onChanged),
        ],
      ),
    );
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
    if (!chart.supportsGauge(gauge)) {
      return '$label: ${_fmtTrim(gauge)}" / out of range';
    }
    return '$label: ${_fmtTrim(gauge)}" / ${chart.barrelsAt(gauge).round()} bbl';
  }

  String _composeText() {
    final primaryGauge = _parseGaugeOrNull(_primaryGauge.text);
    final padName = _activeJob?.padName.trim() ?? '';
    final company = _customer.text.trim();
    final wellName = _wellName.text.trim();

    final lines = <String>[];

    lines.add('${_formatTime(_selectedTime)} $_workflowLabel $_modeLabel');
    if (company.isNotEmpty) lines.add(company);
    if (padName.isNotEmpty) lines.add(padName);
    if (wellName.isNotEmpty) lines.add(wellName);

    if (_showStatus && (_status ?? '').trim().isNotEmpty) {
      lines.add('Status: ${_status!.trim()}');
    }
    if (_showStatus && _showPlugNumber && _hasEnteredValue(_plugNumber.text)) {
      lines.add('Plug #: ${_plugNumber.text.trim()}');
    }
    if (_showStatus && _showCoilDepth && _hasEnteredValue(_coilDepth.text)) {
      lines.add('Coil Depth: ${_coilDepth.text.trim()} ft');
    }
    if (_showGas) {
      final gasValue = (_gas ?? '').trim();
      lines.add('Gas: ${gasValue.isEmpty ? '-' : gasValue}');
    }
    if (_showSand) {
      final sandValue = (_sand ?? '').trim();
      lines.add('Sand: ${sandValue.isEmpty ? '-' : sandValue}');
    }
    if (!_choke.isNone) {
      lines.add('Choke: ${formatChokeDisplay(_choke)}');
    }

    lines.add('Rate: ${_fmtTrim(_resolvedRateBblPerMin())} BBL/min');

    if (_includeManifoldPsi && _hasEnteredValue(_manifoldPsi.text)) {
      lines.add('Manifold PSI: ${_manifoldPsi.text.trim()}');
    }
    if (_includeCasingPsi && _hasEnteredValue(_casingPsi.text)) {
      lines.add('Casing PSI: ${_casingPsi.text.trim()}');
    }
    if (_includePumpPsi && _hasEnteredValue(_pumpPsi.text)) {
      lines.add('Pump PSI: ${_pumpPsi.text.trim()}');
    }
    if (_includeSurfaceTotalFluid &&
        _hasEnteredValue(_surfaceTotalFluid.text)) {
      lines.add(
          'Surface Total Fluid: ${_fmtWholeBbl(_surfaceTotalFluid.text)} bbl');
    }
    if (_includeWaterHauled && _hasEnteredValue(_waterHauled.text)) {
      lines.add('Water Hauled: ${_fmtWholeBbl(_waterHauled.text)} bbl');
    }
    if (_includeOilHauled && _hasEnteredValue(_oilHauled.text)) {
      lines.add('Oil Hauled: ${_fmtWholeBbl(_oilHauled.text)} bbl');
    }

    lines.add('Tank Inventory');
    lines.add(
        _inventoryLine(_primaryTankLabel(), primaryGauge, _primaryChart()));

    if (_showGasTank) {
      final gauge = _parseGaugeOrNull(_gas1Gauge.text);
      if (gauge != null) {
        lines.add(_inventoryLine('Gas Tank', gauge, menardGasTankChart));
      }
    }
    if (_showGasTank2) {
      final gauge = _parseGaugeOrNull(_gas2Gauge.text);
      if (gauge != null) {
        lines.add(_inventoryLine('Gas Tank 2', gauge, menardGasTankChart));
      }
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

    if (_hasEnteredValue(_notes.text)) {
      lines.add('Notes: ${_notes.text.trim()}');
    }

    return lines.where((line) => line.trim().isNotEmpty).join('\n');
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
      _manifoldPsi.clear();
      _casingPsi.clear();
      _pumpPsi.clear();
      _primaryGauge.clear();
      _gas1Gauge.clear();
      _gas2Gauge.clear();
      _water1Gauge.clear();
      _water2Gauge.clear();
      _status = null;
      _gas = null;
      _sand = null;
      _plugNumber.clear();
      _coilDepth.clear();
      _notes.clear();
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
              'This will remove Company/Customer, Well Name, primary tank selection, optional tank configuration, selected choke, and saved Drillout/Cleanout layout for this active setup.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Workflow Setup'),
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
      _includeRateOverride = false;
      _includeSurfaceTotalFluid = false;
      _includeWaterHauled = false;
      _includeOilHauled = false;
      _includeManifoldPsi = false;
      _includeCasingPsi = false;
      _includePumpPsi = false;
      _showStatus = false;
      _showPlugNumber = false;
      _showCoilDepth = false;
      _showGas = false;
      _showSand = false;
      _mode = _DrilloutMode.shiftChange;
      _status = null;
      _gas = null;
      _sand = null;
      _selectedTime = DateTime(2000, 1, 1, _defaultShiftHour);
      _rate.clear();
      _surfaceTotalFluid.clear();
      _waterHauled.clear();
      _oilHauled.clear();
      _manifoldPsi.clear();
      _casingPsi.clear();
      _pumpPsi.clear();
      _plugNumber.clear();
      _coilDepth.clear();
      _notes.clear();
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
    final barrelText = gauge == null
        ? '—'
        : (chart.supportsGauge(gauge)
            ? '${_fmtTrim(chart.barrelsAt(gauge))} bbl'
            : 'Out of range');

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
    _activeCompanyService.activeCompany
        .removeListener(_handleActiveCompanyChanged);
    _customer.dispose();
    _wellName.dispose();
    _rate.dispose();
    _surfaceTotalFluid.dispose();
    _waterHauled.dispose();
    _oilHauled.dispose();
    _manifoldPsi.dispose();
    _casingPsi.dispose();
    _pumpPsi.dispose();
    _plugNumber.dispose();
    _coilDepth.dispose();
    _notes.dispose();
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
      appBar: AppHeader(
        title: _workflowTitle,
        showBack: true,
      ),
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
                        Text(
                          _workflowTitle.toUpperCase(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 20),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<ActiveWorkflowMode>(
                          key: const Key('drillout-cleanout-workflow-selector'),
                          style: ButtonStyle(
                            minimumSize:
                                WidgetStateProperty.all(const Size(0, 48)),
                          ),
                          segments: const [
                            ButtonSegment<ActiveWorkflowMode>(
                              value: ActiveWorkflowMode.drillout,
                              label: Text('Drillout'),
                            ),
                            ButtonSegment<ActiveWorkflowMode>(
                              value: ActiveWorkflowMode.cleanout,
                              label: Text('Cleanout'),
                            ),
                          ],
                          selected: {_workflow},
                          onSelectionChanged: (selection) async {
                            final selected = selection.first;
                            if (selected == _workflow) return;
                            setState(() {
                              _workflow = selected;
                            });
                            await _workflowModeService.setMode(selected);
                          },
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<_DrilloutMode>(
                          key: const Key('drillout-mode-selector'),
                          style: ButtonStyle(
                            minimumSize:
                                WidgetStateProperty.all(const Size(0, 48)),
                          ),
                          segments: const [
                            ButtonSegment<_DrilloutMode>(
                              value: _DrilloutMode.shiftChange,
                              label: Text('Shift Change'),
                            ),
                            ButtonSegment<_DrilloutMode>(
                              value: _DrilloutMode.update,
                              label: Text('Update'),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (selection) {
                            final selected = selection.first;
                            if (selected == _mode) return;
                            setState(() {
                              _mode = selected;
                              _editedText = '';
                            });
                            _saveSetup();
                          },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _customer,
                          readOnly: true,
                          enableInteractiveSelection: false,
                          decoration: const InputDecoration(
                            labelText: 'Company / Customer',
                          ),
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
                        const SizedBox(height: 10),
                        _optionalToggleRow(
                          key: const Key(
                              'drillout-toggle-include-rate-override'),
                          label: 'Include Rate Override',
                          value: _includeRateOverride,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _includeRateOverride = next,
                          ),
                        ),
                        if (_includeRateOverride)
                          TextField(
                            key: const Key('drillout-rate-override-field'),
                            controller: _rate,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Rate Override (bbl/min)',
                            ),
                          ),
                        _optionalToggleRow(
                          key:
                              const Key('drillout-toggle-include-manifold-psi'),
                          label: 'Include Manifold PSI',
                          value: _includeManifoldPsi,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _includeManifoldPsi = next,
                          ),
                        ),
                        if (_includeManifoldPsi)
                          TextField(
                            key: const Key('drillout-manifold-psi-field'),
                            controller: _manifoldPsi,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Manifold PSI',
                            ),
                          ),
                        _optionalToggleRow(
                          key: const Key('drillout-toggle-include-casing-psi'),
                          label: 'Include Casing PSI',
                          value: _includeCasingPsi,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _includeCasingPsi = next,
                          ),
                        ),
                        if (_includeCasingPsi)
                          TextField(
                            key: const Key('drillout-casing-psi-field'),
                            controller: _casingPsi,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Casing PSI',
                            ),
                          ),
                        _optionalToggleRow(
                          key: const Key('drillout-toggle-include-pump-psi'),
                          label: 'Include Pump PSI',
                          value: _includePumpPsi,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _includePumpPsi = next,
                          ),
                        ),
                        if (_includePumpPsi)
                          TextField(
                            key: const Key('drillout-pump-psi-field'),
                            controller: _pumpPsi,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Pump PSI',
                            ),
                          ),
                        _optionalToggleRow(
                          key: const Key(
                              'drillout-toggle-include-surface-total-fluid'),
                          label: 'Include Surface Total Fluid',
                          value: _includeSurfaceTotalFluid,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _includeSurfaceTotalFluid = next,
                          ),
                        ),
                        if (_includeSurfaceTotalFluid)
                          TextField(
                            key:
                                const Key('drillout-surface-total-fluid-field'),
                            controller: _surfaceTotalFluid,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Surface Total Fluid (bbl)',
                            ),
                          ),
                        _optionalToggleRow(
                          key:
                              const Key('drillout-toggle-include-water-hauled'),
                          label: 'Include Water Hauled',
                          value: _includeWaterHauled,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _includeWaterHauled = next,
                          ),
                        ),
                        if (_includeWaterHauled)
                          TextField(
                            key: const Key('drillout-water-hauled-field'),
                            controller: _waterHauled,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Water Hauled (bbl)',
                            ),
                          ),
                        _optionalToggleRow(
                          key: const Key('drillout-toggle-include-oil-hauled'),
                          label: 'Include Oil Hauled',
                          value: _includeOilHauled,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _includeOilHauled = next,
                          ),
                        ),
                        if (_includeOilHauled)
                          TextField(
                            key: const Key('drillout-oil-hauled-field'),
                            controller: _oilHauled,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Oil Hauled (bbl)',
                            ),
                          ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        _optionalToggleRow(
                          key: const Key('drillout-toggle-status'),
                          label: 'Include Status',
                          value: _showStatus,
                          onChanged: (value) => _onOptionalToggleChanged(
                            nextValue: value,
                            assign: (next) => _showStatus = next,
                          ),
                        ),
                        if (_showStatus)
                          DropdownButtonFormField<String>(
                            key: const Key('drillout-status-dropdown'),
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items: _statusOptions
                                .map((option) => DropdownMenuItem<String>(
                                      value: option,
                                      child: Text(option),
                                    ))
                                .toList(growable: false),
                            onChanged: (value) {
                              setState(() => _status = _validatedStatus(value));
                              _saveSetup();
                            },
                          ),
                        if (_showStatus)
                          _optionalToggleRow(
                            key: const Key('drillout-toggle-plug-number'),
                            label: 'Include Plug Number',
                            value: _showPlugNumber,
                            onChanged: (value) => _onOptionalToggleChanged(
                              nextValue: value,
                              assign: (next) => _showPlugNumber = next,
                            ),
                          ),
                        if (_showStatus && _showPlugNumber)
                          TextField(
                            key: const Key('drillout-plug-number-field'),
                            controller: _plugNumber,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _saveSetup(),
                            decoration:
                                const InputDecoration(labelText: 'Plug Number'),
                          ),
                        if (_showStatus)
                          _optionalToggleRow(
                            key: const Key('drillout-toggle-coil-depth'),
                            label: 'Include Coil Depth',
                            value: _showCoilDepth,
                            onChanged: (value) => _onOptionalToggleChanged(
                              nextValue: value,
                              assign: (next) => _showCoilDepth = next,
                            ),
                          ),
                        if (_showStatus && _showCoilDepth)
                          TextField(
                            key: const Key('drillout-coil-depth-field'),
                            controller: _coilDepth,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _saveSetup(),
                            decoration: const InputDecoration(
                              labelText: 'Coil Depth',
                              suffixText: 'ft',
                            ),
                          ),
                        SwitchListTile.adaptive(
                          key: const Key('drillout-toggle-gas'),
                          value: _showGas,
                          onChanged: (value) {
                            setState(() => _showGas = value);
                            _saveSetup();
                          },
                          title: const Text('Gas'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_showGas)
                          DropdownButtonFormField<String>(
                            key: const Key('drillout-gas-dropdown'),
                            initialValue: _gas,
                            decoration: const InputDecoration(
                              labelText: 'Gas',
                            ),
                            items: _gasOptions
                                .map((option) => DropdownMenuItem<String>(
                                      value: option,
                                      child: Text(option),
                                    ))
                                .toList(growable: false),
                            onChanged: (value) {
                              setState(() => _gas = _validatedGas(value));
                              _saveSetup();
                            },
                          ),
                        SwitchListTile.adaptive(
                          key: const Key('drillout-toggle-sand'),
                          value: _showSand,
                          onChanged: (value) {
                            setState(() => _showSand = value);
                            _saveSetup();
                          },
                          title: const Text('Sand'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_showSand)
                          DropdownButtonFormField<String>(
                            key: const Key('drillout-sand-dropdown'),
                            initialValue: _sand,
                            decoration: const InputDecoration(
                              labelText: 'Sand',
                            ),
                            items: _sandOptions
                                .map((option) => DropdownMenuItem<String>(
                                      value: option,
                                      child: Text(option),
                                    ))
                                .toList(growable: false),
                            onChanged: (value) {
                              setState(() => _sand = _validatedSand(value));
                              _saveSetup();
                            },
                          ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const Key('drillout-notes-field'),
                          controller: _notes,
                          maxLines: 3,
                          onChanged: (_) => _saveSetup(),
                          decoration: const InputDecoration(labelText: 'Notes'),
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
                            chart: menardGasTankChart,
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
                            chart: menardGasTankChart,
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
                      key: const Key('drillout-action-preview'),
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
                      key: const Key('drillout-action-copy'),
                      onPressed: _copy,
                      icon: const Icon(Icons.copy),
                      label: Text('Copy $_modeLabel'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('drillout-action-clear-current'),
                      onPressed: _clearCurrentShiftValues,
                      icon: const Icon(Icons.layers_clear),
                      label: const Text('Clear Current Shift Values'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('drillout-action-clear-setup'),
                      onPressed: _clearDrilloutSetup,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Clear Workflow Setup'),
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
