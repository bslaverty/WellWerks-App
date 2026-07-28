import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tank_charts.dart';
import '../models/drillout_tank_configuration.dart';
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

enum _DrilloutGaugeTarget {
  primary,
  gas1,
  gas2,
  water1,
  water2,
  flowback3,
  sweep,
  sweep2,
  sweep3,
}

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
  final _sweepGauge = TextEditingController();
  final _flowback3Gauge = TextEditingController();
  final _sweep2Gauge = TextEditingController();
  final _sweep3Gauge = TextEditingController();

  JobSetup? _activeJob;
  DrilloutTankConfiguration _tankConfig = DrilloutTankConfiguration.defaults;
  bool _showGasTank = false;
  bool _showGasTank2 = false;
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

    final jobSetup =
        Map<String, dynamic>.from(activeJob?.drilloutSetup ?? const {});
    dynamic resolveValue(String key) {
      if (saved.containsKey(key)) return saved[key];
      return jobSetup[key];
    }

    final fallbackCustomer = (activeJob?.company.trim().isNotEmpty ?? false)
        ? activeJob!.company.trim()
        : (activeCompany == JobProfileDefaultsService.companyNone
            ? ''
            : activeCompany);
    final fallbackWell = (activeJob?.primaryWell.trim().isNotEmpty ?? false)
        ? activeJob!.primaryWell.trim()
        : ((jobSetup['wellName'] as String?) ?? '').trim();

    final customerText = saved.containsKey('customer')
        ? (saved['customer'] as String? ?? '')
        : fallbackCustomer;
    final wellText = saved.containsKey('wellName')
        ? (saved['wellName'] as String? ?? '')
        : fallbackWell;

    final latestRate = _latestBblPerMinuteFromLogs(prefs);
    final savedRateOverride = ((resolveValue('rateOverride') as String?) ??
            (resolveValue('rate') as String?) ??
            '')
        .trim();
    final savedSurfaceTotalFluid =
        ((resolveValue('surfaceTotalFluid') as String?) ?? '').trim();
    final savedWaterHauled =
        ((resolveValue('waterHauled') as String?) ?? '').trim();
    final savedOilHauled =
        ((resolveValue('oilHauled') as String?) ?? '').trim();
    final savedManifoldPsi =
        ((resolveValue('manifoldPsi') as String?) ?? '').trim();
    final savedCasingPsi =
        ((resolveValue('casingPsi') as String?) ?? '').trim();
    final savedPumpPsi = ((resolveValue('pumpPsi') as String?) ?? '').trim();

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

    final combinedSetup = <String, dynamic>{
      ...jobSetup,
      ...saved,
    };
    final hasLegacyTankOverrides = saved.containsKey('primaryTank') ||
        saved.containsKey('flowbackTankType') ||
        saved.containsKey('showWaterTank') ||
        saved.containsKey('showWaterTank1') ||
        saved.containsKey('showWaterTank2') ||
        saved.containsKey('showSweepTank') ||
        saved.containsKey('waterTankType') ||
        saved.containsKey('waterTank1Type') ||
        saved.containsKey('waterTank2Type');
    if (hasLegacyTankOverrides) {
      combinedSetup.remove('tankConfigurationV1');
    }
    final loadedTankConfig =
        DrilloutTankConfiguration.fromDrilloutSetup(combinedSetup);

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
      _tankConfig = loadedTankConfig;
      _showGasTank = false;
      _showGasTank2 = false;
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
      _status = _validatedStatus(resolveValue('status') as String?);
      _gas = _validatedGas(
        saved['gas'] as String? ?? saved['gasSpotRate'] as String?,
      );
      _sand = _validatedSand(resolveValue('sand') as String?);
      _rate.text = savedRateOverride;
      _surfaceTotalFluid.text = savedSurfaceTotalFluid;
      _waterHauled.text = savedWaterHauled;
      _oilHauled.text = savedOilHauled;
      _manifoldPsi.text = savedManifoldPsi;
      _casingPsi.text = savedCasingPsi;
      _pumpPsi.text = savedPumpPsi;
      _plugNumber.text = resolveValue('plugNumber') as String? ?? '';
      _coilDepth.text = resolveValue('coilDepth') as String? ?? '';
      _notes.text = resolveValue('notes') as String? ?? '';
      _primaryGauge.text =
          loadedTankConfig.gaugesByRole[DrilloutTankCatalog.roleSandTank] ??
              (resolveValue('primaryGauge') as String?) ??
              (resolveValue('flowbackGauge') as String?) ??
              '';
      _gas1Gauge.text = saved['gas1Gauge'] as String? ?? '';
      _gas2Gauge.text = saved['gas2Gauge'] as String? ?? '';
      _water1Gauge.text =
          loadedTankConfig.gaugesByRole[DrilloutTankCatalog.roleFlowback1] ??
              (resolveValue('water1Gauge') as String?) ??
              (resolveValue('waterTank1Gauge') as String?) ??
              '';
      _water2Gauge.text =
          loadedTankConfig.gaugesByRole[DrilloutTankCatalog.roleFlowback2] ??
              (saved['water2Gauge'] as String? ?? '');
      _flowback3Gauge.text =
          loadedTankConfig.gaugesByRole[DrilloutTankCatalog.roleFlowback3] ??
              '';
      _sweepGauge.text =
          loadedTankConfig.gaugesByRole[DrilloutTankCatalog.roleSweep1] ??
              (saved['sweepGauge'] as String? ?? '');
      _sweep2Gauge.text =
          loadedTankConfig.gaugesByRole[DrilloutTankCatalog.roleSweep2] ?? '';
      _sweep3Gauge.text =
          loadedTankConfig.gaugesByRole[DrilloutTankCatalog.roleSweep3] ?? '';
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
    final roleGauges = <String, String>{
      ..._tankConfig.gaugesByRole,
      DrilloutTankCatalog.roleSandTank: _primaryGauge.text.trim(),
      DrilloutTankCatalog.roleFlowback1: _water1Gauge.text.trim(),
      DrilloutTankCatalog.roleFlowback2: _water2Gauge.text.trim(),
      DrilloutTankCatalog.roleFlowback3: _flowback3Gauge.text.trim(),
      DrilloutTankCatalog.roleSweep1: _sweepGauge.text.trim(),
      DrilloutTankCatalog.roleSweep2: _sweep2Gauge.text.trim(),
      DrilloutTankCatalog.roleSweep3: _sweep3Gauge.text.trim(),
    };
    final configWithGauges = _tankConfig.copyWith(gaugesByRole: roleGauges);
    final legacyCompat = configWithGauges.toLegacyCompatJson();
    await prefs.setString(
      _jobScopedKey,
      jsonEncode({
        'customer': _customer.text.trim(),
        'wellName': _wellName.text.trim(),
        'primaryTank': legacyCompat['flowbackTankType'],
        'showGasTank': _showGasTank,
        'showGasTank2': _showGasTank2,
        'showWaterTank': legacyCompat['showWaterTank1'],
        'showWaterTank2': legacyCompat['showWaterTank2'],
        'showSweepTank': legacyCompat['showSweepTank'],
        'waterTankType': legacyCompat['waterTank1Type'],
        'waterTank2Type': legacyCompat['waterTank2Type'],
        'tankConfigurationV1': configWithGauges.toJson(),
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
        'primaryGauge': _primaryGauge.text.trim(),
        'gas1Gauge': _gas1Gauge.text.trim(),
        'gas2Gauge': _gas2Gauge.text.trim(),
        'water1Gauge': _water1Gauge.text.trim(),
        'water2Gauge': _water2Gauge.text.trim(),
        'flowback3Gauge': _flowback3Gauge.text.trim(),
        'sweepGauge': _sweepGauge.text.trim(),
        'sweep2Gauge': _sweep2Gauge.text.trim(),
        'sweep3Gauge': _sweep3Gauge.text.trim(),
        ...legacyCompat,
      }),
    );

    final active = _activeJob;
    if (active != null) {
      await _jobStorage.updateActiveJob(
        active.copyWith(
          workflow: _workflow == ActiveWorkflowMode.cleanout
              ? 'cleanout'
              : 'drillout',
          padName: active.padName.trim(),
          wells: _wellName.text.trim().isEmpty
              ? active.wells
              : <String>[_wellName.text.trim()],
          wellEntries: _wellName.text.trim().isEmpty
              ? active.wellEntries
              : <JobSetupWell>[
                  JobSetupWell(
                    id: active.wellEntries.isEmpty
                        ? JobSetup.generateWellId()
                        : active.wellEntries.first.id,
                    name: _wellName.text.trim(),
                  ),
                ],
          drilloutSetup: {
            ...active.drilloutSetup,
            'wellName': _wellName.text.trim(),
            'locationPad': active.padName,
            'manifoldPsi': _manifoldPsi.text.trim(),
            'casingPsi': _casingPsi.text.trim(),
            'pumpPsi': _pumpPsi.text.trim(),
            'rateOverride': _rate.text.trim(),
            'surfaceTotalFluid': _surfaceTotalFluid.text.trim(),
            'waterHauled': _waterHauled.text.trim(),
            'oilHauled': _oilHauled.text.trim(),
            'plugNumber': _plugNumber.text.trim(),
            'status': _status ?? '',
            'coilDepth': _coilDepth.text.trim(),
            'tankConfigurationV1': configWithGauges.toJson(),
            'flowbackGauge': _primaryGauge.text.trim(),
            'waterTank1Gauge': _water1Gauge.text.trim(),
            'waterTank2Gauge': _water2Gauge.text.trim(),
            'flowback3Gauge': _flowback3Gauge.text.trim(),
            'sweepTankGauge': _sweepGauge.text.trim(),
            'sweep2Gauge': _sweep2Gauge.text.trim(),
            'sweep3Gauge': _sweep3Gauge.text.trim(),
            ...legacyCompat,
          },
        ),
      );
    }
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
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
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

  TankChart _chartForType(String typeId) {
    final normalized = DrilloutTankCatalog.normalizeLegacyType(typeId);
    switch (normalized) {
      case DrilloutTankCatalog.typeFs3:
        return fs3Chart;
      case DrilloutTankCatalog.typeFlowbackVBottom:
        return flowback500Chart;
      case DrilloutTankCatalog.typeFlowbackRoundBottom:
        return flowbackRoundBottomChart;
      case DrilloutTankCatalog.typeSandX:
      default:
        return sandXChart;
    }
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
      case _DrilloutGaugeTarget.flowback3:
        return _flowback3Gauge;
      case _DrilloutGaugeTarget.sweep:
        return _sweepGauge;
      case _DrilloutGaugeTarget.sweep2:
        return _sweep2Gauge;
      case _DrilloutGaugeTarget.sweep3:
        return _sweep3Gauge;
      case null:
        return null;
    }
  }

  String get _activeGaugeLabel {
    switch (_activeGaugeTarget) {
      case _DrilloutGaugeTarget.primary:
        return DrilloutTankCatalog.roleById(DrilloutTankCatalog.roleSandTank)
            .label;
      case _DrilloutGaugeTarget.gas1:
        return 'Gas Tank';
      case _DrilloutGaugeTarget.gas2:
        return 'Gas Tank 2';
      case _DrilloutGaugeTarget.water1:
        return DrilloutTankCatalog.roleById(DrilloutTankCatalog.roleFlowback1)
            .label;
      case _DrilloutGaugeTarget.water2:
        return DrilloutTankCatalog.roleById(DrilloutTankCatalog.roleFlowback2)
            .label;
      case _DrilloutGaugeTarget.flowback3:
        return 'Flowback Tank 3';
      case _DrilloutGaugeTarget.sweep:
        return DrilloutTankCatalog.roleById(DrilloutTankCatalog.roleSweep1)
            .label;
      case _DrilloutGaugeTarget.sweep2:
        return DrilloutTankCatalog.roleById(DrilloutTankCatalog.roleSweep2)
            .label;
      case _DrilloutGaugeTarget.sweep3:
        return DrilloutTankCatalog.roleById(DrilloutTankCatalog.roleSweep3)
            .label;
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
    _saveSetup();
  }

  void _backspaceGauge() {
    final controller = _activeGaugeController;
    if (controller == null || controller.text.isEmpty) return;
    setState(() {
      controller.value = GaugeKeypadInput.backspace(controller.value);
    });
    _saveSetup();
  }

  void _clearActiveGauge() {
    final controller = _activeGaugeController;
    if (controller == null) return;
    setState(controller.clear);
    _saveSetup();
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

  TextEditingController? _gaugeControllerForRole(String roleId) {
    switch (roleId) {
      case DrilloutTankCatalog.roleSandTank:
        return _primaryGauge;
      case DrilloutTankCatalog.roleFlowback1:
        return _water1Gauge;
      case DrilloutTankCatalog.roleFlowback2:
        return _water2Gauge;
      case DrilloutTankCatalog.roleFlowback3:
        return _flowback3Gauge;
      case DrilloutTankCatalog.roleSweep1:
        return _sweepGauge;
      case DrilloutTankCatalog.roleSweep2:
        return _sweep2Gauge;
      case DrilloutTankCatalog.roleSweep3:
        return _sweep3Gauge;
      default:
        return null;
    }
  }

  _DrilloutGaugeTarget _targetForRole(String roleId) {
    switch (roleId) {
      case DrilloutTankCatalog.roleSandTank:
        return _DrilloutGaugeTarget.primary;
      case DrilloutTankCatalog.roleFlowback1:
        return _DrilloutGaugeTarget.water1;
      case DrilloutTankCatalog.roleFlowback2:
        return _DrilloutGaugeTarget.water2;
      case DrilloutTankCatalog.roleFlowback3:
        return _DrilloutGaugeTarget.flowback3;
      case DrilloutTankCatalog.roleSweep1:
        return _DrilloutGaugeTarget.sweep;
      case DrilloutTankCatalog.roleSweep2:
        return _DrilloutGaugeTarget.sweep2;
      case DrilloutTankCatalog.roleSweep3:
        return _DrilloutGaugeTarget.sweep3;
      default:
        return _DrilloutGaugeTarget.primary;
    }
  }

  List<DrilloutTankSelection> _activeTankSelections() {
    final gauges = <String, String>{
      ..._tankConfig.gaugesByRole,
      DrilloutTankCatalog.roleSandTank: _primaryGauge.text.trim(),
      DrilloutTankCatalog.roleFlowback1: _water1Gauge.text.trim(),
      DrilloutTankCatalog.roleFlowback2: _water2Gauge.text.trim(),
      DrilloutTankCatalog.roleFlowback3: _flowback3Gauge.text.trim(),
      DrilloutTankCatalog.roleSweep1: _sweepGauge.text.trim(),
      DrilloutTankCatalog.roleSweep2: _sweep2Gauge.text.trim(),
      DrilloutTankCatalog.roleSweep3: _sweep3Gauge.text.trim(),
    };
    return _tankConfig.copyWith(gaugesByRole: gauges).activeSelections;
  }

  List<DropdownMenuItem<String>> _tankTypeItemsForRole(String roleId) {
    final role = DrilloutTankCatalog.roleById(roleId);
    return role.allowedTypeIds
        .map(
          (typeId) => DropdownMenuItem<String>(
            value: typeId,
            child: Text(DrilloutTankCatalog.typeById(typeId).label),
          ),
        )
        .toList(growable: false);
  }

  Future<bool> _confirmTankRoleReduction(List<String> removedRoleIds) async {
    bool hasData = false;
    for (final roleId in removedRoleIds) {
      final controller = _gaugeControllerForRole(roleId);
      if (controller != null && controller.text.trim().isNotEmpty) {
        hasData = true;
        break;
      }
      if ((_tankConfig.gaugesByRole[roleId] ?? '').trim().isNotEmpty) {
        hasData = true;
        break;
      }
    }
    if (!hasData) return true;

    final labels = removedRoleIds
        .map((id) => DrilloutTankCatalog.roleById(id).label)
        .join(', ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Tank Slots?'),
        content: Text(
          'Reducing tank quantity will remove $labels and any associated readings/history for those roles. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _setFlowbackTankCount(int count) async {
    final current = _tankConfig.flowbackCount;
    if (count >= current) {
      final next = List<String>.from(_tankConfig.flowbackTankTypes);
      while (next.length < count) {
        next.add(DrilloutTankCatalog.typeFlowbackRoundBottom);
      }
      setState(() {
        _tankConfig = _tankConfig.copyWith(flowbackTankTypes: next);
      });
      _saveSetup();
      return;
    }

    final removedRoles = DrilloutTankCatalog.flowbackRoleIds.sublist(count);
    final confirmed = await _confirmTankRoleReduction(removedRoles);
    if (!confirmed) return;

    setState(() {
      _tankConfig = _tankConfig.copyWith(
        flowbackTankTypes: _tankConfig.flowbackTankTypes.sublist(0, count),
      );
    });
    _saveSetup();
  }

  Future<void> _setSweepTankCount(int count) async {
    final current = _tankConfig.sweepCount;
    if (count >= current) {
      final next = List<String>.from(_tankConfig.sweepTankTypes);
      while (next.length < count) {
        next.add(DrilloutTankCatalog.typeFlowbackRoundBottom);
      }
      setState(() {
        _tankConfig = _tankConfig.copyWith(sweepTankTypes: next);
      });
      _saveSetup();
      return;
    }

    final removedRoles = DrilloutTankCatalog.sweepRoleIds.sublist(count);
    final confirmed = await _confirmTankRoleReduction(removedRoles);
    if (!confirmed) return;

    setState(() {
      _tankConfig = _tankConfig.copyWith(
        sweepTankTypes: _tankConfig.sweepTankTypes.sublist(0, count),
      );
    });
    _saveSetup();
  }

  double? _barrelsForGauge(double? gauge, TankChart chart) {
    if (gauge == null) return null;
    if (!chart.supportsGauge(gauge)) return null;
    return chart.barrelsAt(gauge);
  }

  String _composeText() {
    final padName = _activeJob?.padName.trim() ?? '';
    final company = _customer.text.trim();
    final wellName = _wellName.text.trim();

    final headerLines = <String>[
      '${_formatTime(_selectedTime)} $_workflowLabel $_modeLabel',
    ];
    if (company.isNotEmpty) headerLines.add(company);
    if (padName.isNotEmpty) headerLines.add(padName);
    if (wellName.isNotEmpty) headerLines.add(wellName);

    final detailLines = <String>[];
    if (_showStatus && (_status ?? '').trim().isNotEmpty) {
      detailLines.add('Status: ${_status!.trim()}');
    }
    if (_showStatus && _showPlugNumber && _hasEnteredValue(_plugNumber.text)) {
      detailLines.add('Plug #: ${_plugNumber.text.trim()}');
    }
    if (_showStatus && _showCoilDepth && _hasEnteredValue(_coilDepth.text)) {
      detailLines.add('Coil Depth: ${_coilDepth.text.trim()} ft');
    }
    if (_showGas) {
      final gasValue = (_gas ?? '').trim();
      detailLines.add('Gas: ${gasValue.isEmpty ? '-' : gasValue}');
    }
    if (_showSand) {
      final sandValue = (_sand ?? '').trim();
      detailLines.add('Sand: ${sandValue.isEmpty ? '-' : sandValue}');
    }
    if (!_choke.isNone) {
      detailLines.add('Choke: ${formatChokeDisplay(_choke)}');
    }

    detailLines.add('Rate: ${_fmtTrim(_resolvedRateBblPerMin())} BBL/min');

    if (_includeManifoldPsi && _hasEnteredValue(_manifoldPsi.text)) {
      detailLines.add('Manifold PSI: ${_manifoldPsi.text.trim()}');
    }
    if (_includeCasingPsi && _hasEnteredValue(_casingPsi.text)) {
      detailLines.add('Casing PSI: ${_casingPsi.text.trim()}');
    }
    if (_includePumpPsi && _hasEnteredValue(_pumpPsi.text)) {
      detailLines.add('Pump PSI: ${_pumpPsi.text.trim()}');
    }
    if (_includeSurfaceTotalFluid &&
        _hasEnteredValue(_surfaceTotalFluid.text)) {
      detailLines.add(
          'Surface Total Fluid: ${_fmtWholeBbl(_surfaceTotalFluid.text)} bbl');
    }
    if (_includeWaterHauled && _hasEnteredValue(_waterHauled.text)) {
      detailLines.add('Water Hauled: ${_fmtWholeBbl(_waterHauled.text)} bbl');
    }
    if (_includeOilHauled && _hasEnteredValue(_oilHauled.text)) {
      detailLines.add('Oil Hauled: ${_fmtWholeBbl(_oilHauled.text)} bbl');
    }

    final tankRows = <({String label, double? gauge, TankChart chart})>[];
    for (final selection in _activeTankSelections()) {
      final role = DrilloutTankCatalog.roleById(selection.roleId);
      tankRows.add((
        label: role.label,
        gauge: _parseGaugeOrNull(selection.gauge),
        chart: _chartForType(selection.typeId),
      ));
    }

    final maxLabel = tankRows.isEmpty
        ? 0
        : tankRows
            .map((row) => row.label.length)
            .reduce((a, b) => a > b ? a : b);
    final inventoryLines = <String>['Tank Inventory', ''];

    double totalBarrels = 0;
    for (final row in tankRows) {
      final barrels = _barrelsForGauge(row.gauge, row.chart);
      if (barrels != null) totalBarrels += barrels;
      final gaugeText = row.gauge == null ? '-' : '${_fmtTrim(row.gauge!)}"';
      final barrelText = barrels == null ? '-' : '${barrels.round()} bbl';
      inventoryLines.add(
        '${row.label.padLeft(maxLabel)}: ${gaugeText.padLeft(8)} - ${barrelText.padLeft(7)}',
      );
    }

    inventoryLines.add('');
    inventoryLines.add(
      tankRows.isEmpty
          ? 'Total On Location: -'
          : 'Total On Location: ${totalBarrels.round()} bbl',
    );

    final blocks = <String>[
      headerLines.where((line) => line.trim().isNotEmpty).join('\n'),
      if (detailLines.isNotEmpty) detailLines.join('\n'),
      inventoryLines.join('\n'),
      if (_hasEnteredValue(_notes.text)) 'Notes: ${_notes.text.trim()}',
    ];

    return blocks.where((block) => block.trim().isNotEmpty).join('\n\n');
  }

  String _currentOutputText() {
    return _editedText.trim().isNotEmpty ? _editedText : _composeText();
  }

  Future<void> _preview() async {
    final text = _currentOutputText();
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
    final text = _currentOutputText();
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
      _sweepGauge.clear();
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
              'This will remove Company/Customer, Well Name, tank configuration, selected choke, and saved Drillout/Cleanout layout for this active setup.',
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
      _tankConfig = DrilloutTankConfiguration.defaults;
      _showGasTank = false;
      _showGasTank2 = false;
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
      _flowback3Gauge.clear();
      _sweepGauge.clear();
      _sweep2Gauge.clear();
      _sweep3Gauge.clear();
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
              onChanged: (_) {
                setState(() {});
                _saveSetup();
              },
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
    _flowback3Gauge.dispose();
    _sweepGauge.dispose();
    _sweep2Gauge.dispose();
    _sweep3Gauge.dispose();
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
                          key: const Key('drillout-tank-sand-type'),
                          initialValue: _tankConfig.sandTankType,
                          decoration: const InputDecoration(
                              labelText: 'Sand Tank Type'),
                          items: _tankTypeItemsForRole(
                            DrilloutTankCatalog.roleSandTank,
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _tankConfig = _tankConfig.copyWith(
                                sandTankType: value,
                              );
                            });
                            _saveSetup();
                          },
                        ),
                        const SizedBox(height: 8),
                        _gaugeCard(
                          title: DrilloutTankCatalog.roleById(
                            DrilloutTankCatalog.roleSandTank,
                          ).label,
                          chart: _chartForType(_tankConfig.sandTankType),
                          controller: _primaryGauge,
                          target: _DrilloutGaugeTarget.primary,
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          key: const Key('drillout-tank-flowback-count'),
                          initialValue: _tankConfig.flowbackCount,
                          decoration: const InputDecoration(
                            labelText: 'Flowback Tank Quantity',
                          ),
                          items: const [
                            DropdownMenuItem<int>(value: 0, child: Text('0')),
                            DropdownMenuItem<int>(value: 1, child: Text('1')),
                            DropdownMenuItem<int>(value: 2, child: Text('2')),
                            DropdownMenuItem<int>(value: 3, child: Text('3')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _setFlowbackTankCount(value);
                          },
                        ),
                        for (int i = 0; i < _tankConfig.flowbackCount; i++)
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: Key('drillout-tank-flowback-type-$i'),
                                initialValue: _tankConfig.flowbackTankTypes[i],
                                decoration: InputDecoration(
                                  labelText: 'Flowback Tank ${i + 1} Type',
                                ),
                                items: _tankTypeItemsForRole(
                                  DrilloutTankCatalog.flowbackRoleIds[i],
                                ),
                                onChanged: (value) {
                                  if (value == null) return;
                                  final types = List<String>.from(
                                      _tankConfig.flowbackTankTypes);
                                  types[i] = value;
                                  setState(() {
                                    _tankConfig = _tankConfig.copyWith(
                                      flowbackTankTypes: types,
                                    );
                                  });
                                  _saveSetup();
                                },
                              ),
                              const SizedBox(height: 8),
                              _gaugeCard(
                                title: DrilloutTankCatalog.roleById(
                                  DrilloutTankCatalog.flowbackRoleIds[i],
                                ).label,
                                chart: _chartForType(
                                  _tankConfig.flowbackTankTypes[i],
                                ),
                                controller: _gaugeControllerForRole(
                                      DrilloutTankCatalog.flowbackRoleIds[i],
                                    ) ??
                                    _water1Gauge,
                                target: _targetForRole(
                                  DrilloutTankCatalog.flowbackRoleIds[i],
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          key: const Key('drillout-tank-sweep-count'),
                          initialValue: _tankConfig.sweepCount,
                          decoration: const InputDecoration(
                            labelText: 'Sweep Tank Quantity',
                          ),
                          items: const [
                            DropdownMenuItem<int>(value: 0, child: Text('0')),
                            DropdownMenuItem<int>(value: 1, child: Text('1')),
                            DropdownMenuItem<int>(value: 2, child: Text('2')),
                            DropdownMenuItem<int>(value: 3, child: Text('3')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _setSweepTankCount(value);
                          },
                        ),
                        for (int i = 0; i < _tankConfig.sweepCount; i++)
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: Key('drillout-tank-sweep-type-$i'),
                                initialValue: _tankConfig.sweepTankTypes[i],
                                decoration: InputDecoration(
                                  labelText: 'Sweep Tank ${i + 1} Type',
                                ),
                                items: _tankTypeItemsForRole(
                                  DrilloutTankCatalog.sweepRoleIds[i],
                                ),
                                onChanged: (value) {
                                  if (value == null) return;
                                  final types = List<String>.from(
                                      _tankConfig.sweepTankTypes);
                                  types[i] = value;
                                  setState(() {
                                    _tankConfig = _tankConfig.copyWith(
                                      sweepTankTypes: types,
                                    );
                                  });
                                  _saveSetup();
                                },
                              ),
                              const SizedBox(height: 8),
                              _gaugeCard(
                                title: DrilloutTankCatalog.roleById(
                                  DrilloutTankCatalog.sweepRoleIds[i],
                                ).label,
                                chart: _chartForType(
                                    _tankConfig.sweepTankTypes[i]),
                                controller: _gaugeControllerForRole(
                                      DrilloutTankCatalog.sweepRoleIds[i],
                                    ) ??
                                    _sweepGauge,
                                target: _targetForRole(
                                  DrilloutTankCatalog.sweepRoleIds[i],
                                ),
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
