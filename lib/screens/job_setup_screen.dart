import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../models/drillout_tank_configuration.dart';
import '../models/job_setup.dart';
import '../models/operations_log_entry.dart';
import 'home_screen.dart';
import '../services/active_company_service.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_history_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_service.dart';
import '../services/production_shift_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class JobSetupScreen extends StatefulWidget {
  const JobSetupScreen({
    super.key,
    this.startFreshJob = false,
    this.editActiveOnOpen = false,
  });

  final bool startFreshJob;
  final bool editActiveOnOpen;

  @override
  State<JobSetupScreen> createState() => _JobSetupScreenState();
}

class _JobSetupScreenState extends State<JobSetupScreen> {
  static const String _gasRateSourceAccumulation = 'gasAccumulation';
  static const String _gasRateSourceInstantSpot = 'instantSpotRate';
  static const String _flowPathFlare = 'flare';
  static const String _flowPathEcd = 'ecd';
  static const String _wellStatusNotStarted = JobSetup.wellStatusNotStarted;
  static const String _wellStatusActive = JobSetup.wellStatusActive;
  static const String _wellStatusComplete = JobSetup.wellStatusComplete;

  final _storage = JobStorageService();
  final _profileDefaults = JobProfileDefaultsService();
  final _activeCompanyService = ActiveCompanyService.instance;
  final _workflowModeService = ActiveWorkflowModeService.instance;
  final _historyService = JobHistoryService();
  final _operationsLogService = OperationsLogService();
  final _productionShiftService = ProductionShiftService();
  final _page = PageController();
  Timer? _autoSaveTimer;
  bool _autoSaving = false;
  DateTime? _lastAutoSaveAt;

  int _step = 0;
  bool _loading = true;
  bool _editing = false;
  bool _startingFreshJob = false;
  bool _gpsFilling = false;
  JobSetup? _activeJob;
  ActiveWorkflowMode _activeWorkflowMode = ActiveWorkflowMode.production;

  String company = 'Mach Energy';
  String jobType = JobProfileDefaultsService.jobTypeSingleWell;
  List<String> wellFieldKeys = const [];
  List<String> activeEquipmentSections = const [];
  bool includeNotesSection = true;
  bool flareEcdGasRateEnabled = true;
  String gasRateSource = _gasRateSourceAccumulation;
  String productionFlowPath = _flowPathFlare;
  final selectedChemicals = <String>[];
  String shift = 'Day';
  final padName = TextEditingController();
  final notes = TextEditingController();
  final leaseName = TextEditingController();
  final county = TextEditingController();
  final state = TextEditingController(text: 'Oklahoma');
  final jobLatitude = TextEditingController();
  final jobLongitude = TextEditingController();
  final dateStarted = TextEditingController(
    text: DateFormat('MM/dd/yyyy').format(DateTime.now()),
  );
  final wells = <String>[];
  final wellIds = <String>[];
  final leaseNames = <String>[];
  final wellNameManuallyEdited = <bool>[];
  final _wellNameControllers = <TextEditingController>[];
  final _wellNameFocusNodes = <FocusNode>[];
  final _wellRowKeys = <String, GlobalKey>{};

  final sandSeparators = TextEditingController(text: '2');
  final plugCatchers = TextEditingController(text: '1');
  final chokeManifolds = TextEditingController(text: '1');
  final lineHeaters = TextEditingController(text: '1');
  final testUnits = TextEditingController(text: '1');
  final ecds = TextEditingController(text: '0');
  final vrus = TextEditingController(text: '0');
  final flares = TextEditingController(text: '0');
  final transferPumps = TextEditingController(text: '0');

  final oilTanks = TextEditingController(text: '4');
  final oilTankCapacity = TextEditingController(text: '400');
  final waterTanks = TextEditingController(text: '6');
  final waterTankCapacity = TextEditingController(text: '400');
  final productionTankFactor = TextEditingController(text: '1.67');

  final _drilloutWellName = TextEditingController();
  final _drilloutManifoldPsi = TextEditingController();
  final _drilloutCasingPsi = TextEditingController();
  final _drilloutPumpPsi = TextEditingController();
  final _drilloutRateOverride = TextEditingController();
  final _drilloutSurfaceTotalFluid = TextEditingController();
  final _drilloutWaterHauled = TextEditingController();
  final _drilloutOilHauled = TextEditingController();
  final _drilloutPlugNumber = TextEditingController();
  final _drilloutStatus = TextEditingController();
  final _drilloutCoilDepth = TextEditingController();

  DrilloutTankConfiguration _tankConfig = DrilloutTankConfiguration.defaults;

  final _flowbackGauge = TextEditingController();
  final _waterTank1Gauge = TextEditingController();
  final _waterTank2Gauge = TextEditingController();
  final _sweepTankGauge = TextEditingController();

  List<String> _companyOptions() {
    final options = List<String>.from(_profileDefaults.companyOptions);
    final current = company.trim();
    if (current.isNotEmpty && !options.contains(current)) {
      options.add(current);
    }
    options.sort();
    return options;
  }

  void _setCompany(String value) {
    final normalized = _profileDefaults.normalizeCompany(value);
    setState(() {
      company = normalized;
      final defaults = _profileDefaults.profileForCompany(company);
      wellFieldKeys = List<String>.from(defaults.wellFieldKeys);
      activeEquipmentSections = activeEquipmentSections
          .where(defaults.optionalSections.contains)
          .toList(growable: false);
      if (activeEquipmentSections.isEmpty) {
        activeEquipmentSections =
            List<String>.from(defaults.defaultActiveSections);
      }
    });
    _scheduleAutoSave();
  }

  int _i(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 0;
  }

  String _formatCoordinate(double value) {
    return value.toStringAsFixed(6);
  }

  Future<void> _fillCoordinatesFromCurrentLocation() async {
    if (_gpsFilling) return;
    setState(() => _gpsFilling = true);
    try {
      final locationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!locationEnabled) {
        throw StateError('Location services are disabled.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;
      setState(() {
        jobLatitude.text = _formatCoordinate(position.latitude);
        jobLongitude.text = _formatCoordinate(position.longitude);
      });
      _scheduleAutoSave();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates captured from current GPS.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message
          : 'Unable to capture current GPS coordinates.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.toString())),
      );
    } finally {
      if (!mounted) return;
      setState(() => _gpsFilling = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _attachAutoSaveListeners();
    _load();
  }

  List<TextEditingController> get _autoSaveControllers => [
        padName,
        notes,
        leaseName,
        county,
        state,
        jobLatitude,
        jobLongitude,
        dateStarted,
        sandSeparators,
        plugCatchers,
        chokeManifolds,
        lineHeaters,
        testUnits,
        ecds,
        vrus,
        flares,
        transferPumps,
        oilTanks,
        oilTankCapacity,
        waterTanks,
        waterTankCapacity,
        productionTankFactor,
        _drilloutWellName,
        _drilloutManifoldPsi,
        _drilloutCasingPsi,
        _drilloutPumpPsi,
        _drilloutRateOverride,
        _drilloutSurfaceTotalFluid,
        _drilloutWaterHauled,
        _drilloutOilHauled,
        _drilloutPlugNumber,
        _drilloutStatus,
        _drilloutCoilDepth,
        _flowbackGauge,
        _waterTank1Gauge,
        _waterTank2Gauge,
        _sweepTankGauge,
      ];

  void _attachAutoSaveListeners() {
    for (final controller in _autoSaveControllers) {
      controller.addListener(_scheduleAutoSave);
    }
  }

  void _ensurePerWellCapacity(int count) {
    final normalized = count < 0 ? 0 : count;
    while (wells.length < normalized) {
      wells.add('');
    }
    while (wellIds.length < normalized) {
      wellIds.add(JobSetup.generateWellId());
    }
    while (leaseNames.length < normalized) {
      leaseNames.add('');
    }
    while (wellNameManuallyEdited.length < normalized) {
      wellNameManuallyEdited.add(false);
    }
    while (_wellNameControllers.length < normalized) {
      _wellNameControllers.add(TextEditingController());
    }
    while (_wellNameFocusNodes.length < normalized) {
      _wellNameFocusNodes.add(FocusNode());
    }
    for (final id in wellIds) {
      _wellRowKeys.putIfAbsent(id, () => GlobalKey());
    }

    if (wells.length > normalized) {
      wells.removeRange(normalized, wells.length);
    }
    if (wellIds.length > normalized) {
      wellIds.removeRange(normalized, wellIds.length);
    }
    if (leaseNames.length > normalized) {
      leaseNames.removeRange(normalized, leaseNames.length);
    }
    if (wellNameManuallyEdited.length > normalized) {
      wellNameManuallyEdited.removeRange(
          normalized, wellNameManuallyEdited.length);
    }
    while (_wellNameControllers.length > normalized) {
      _wellNameControllers.removeLast().dispose();
    }
    while (_wellNameFocusNodes.length > normalized) {
      _wellNameFocusNodes.removeLast().dispose();
    }
    final activeIds = wellIds.toSet();
    _wellRowKeys.removeWhere((id, _) => !activeIds.contains(id));

    for (int i = 0; i < normalized; i++) {
      final nextText = i < wells.length ? wells[i] : '';
      if (_wellNameControllers[i].text != nextText) {
        _wellNameControllers[i].text = nextText;
      }
    }
  }

  TextEditingController _wellNameControllerAt(int index) {
    while (_wellNameControllers.length <= index) {
      _wellNameControllers.add(TextEditingController());
    }
    if (index >= 0 && index < wells.length) {
      final nextText = wells[index];
      if (_wellNameControllers[index].text != nextText) {
        _wellNameControllers[index].text = nextText;
      }
    }
    return _wellNameControllers[index];
  }

  FocusNode _wellNameFocusNodeAt(int index) {
    while (_wellNameFocusNodes.length <= index) {
      _wellNameFocusNodes.add(FocusNode());
    }
    if (index >= 0 && index < wellIds.length) {
      _wellRowKeys.putIfAbsent(wellIds[index], () => GlobalKey());
    }
    return _wellNameFocusNodes[index];
  }

  void _focusAndRevealWellAt(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= wellIds.length) return;

      _wellNameFocusNodeAt(index).requestFocus();

      final key = _wellRowKeys[wellIds[index]];
      final rowContext = key?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.9,
        );
      }
    });
  }

  List<Map<String, String>> _draftMultiWellsFromSetup(
      Map<String, dynamic> setup) {
    final raw = setup['draftMultiWellsV1'];
    if (raw is! List) return const <Map<String, String>>[];

    final rows = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      rows.add(<String, String>{
        'id': (item['id'] ?? '').toString().trim(),
        'name': (item['name'] ?? '').toString(),
        'lease': (item['lease'] ?? '').toString(),
      });
    }
    return rows;
  }

  void _syncWellNameFromLease(int index, {bool force = false}) {
    if (index < 0 || index >= wells.length || index >= leaseNames.length) {
      return;
    }
    final lease = leaseNames[index].trim();
    final existing = wells[index].trim();
    final canAutoFill = existing.isEmpty || !wellNameManuallyEdited[index];
    if ((force || canAutoFill) && lease.isNotEmpty) {
      wells[index] = lease;
      wellNameManuallyEdited[index] = false;
      return;
    }
    if (force && lease.isEmpty) {
      wells[index] = '';
      wellNameManuallyEdited[index] = false;
    }
  }

  void _setLeaseNameAt(int index, String value) {
    if (index < 0 || index >= leaseNames.length) return;
    leaseNames[index] = value;
    _syncWellNameFromLease(index);
  }

  void _setWellNameAt(int index, String value) {
    if (index < 0 || index >= wells.length) return;
    wells[index] = value;
    if (value.trim().isEmpty) {
      wellNameManuallyEdited[index] = false;
      _syncWellNameFromLease(index);
      return;
    }
    if (JobSetup.isPlaceholderWellName(value)) {
      wellNameManuallyEdited[index] = false;
      _syncWellNameFromLease(index);
      return;
    }
    final lease = index < leaseNames.length ? leaseNames[index].trim() : '';
    wellNameManuallyEdited[index] = value.trim() != lease;
  }

  Future<void> _load() async {
    await _profileDefaults.ensureCustomProfilesLoaded();
    await _activeCompanyService.ensureLoaded();
    final workflowMode = await _workflowModeService.ensureLoaded();
    final active = await _storage.ensureActiveJobLoaded();
    if (active != null) {
      _applyJobToForm(active);
      _applyDrilloutSetupToForm(active);
    } else {
      final globalCompany = _activeCompanyService.activeCompany.value;
      if (globalCompany.trim().isNotEmpty) {
        company = globalCompany;
      }
      _resetDrilloutSetupForNewJob();
    }

    if (!mounted) return;
    setState(() {
      _activeJob = active;
      _activeWorkflowMode = _workflowFromJob(active, workflowMode);
      _startingFreshJob = widget.startFreshJob;
      _editing =
          widget.startFreshJob || (widget.editActiveOnOpen && active != null);
      _loading = false;
    });

    if (widget.startFreshJob) {
      _resetFormForNewJob();
      _resetDrilloutSetupForNewJob();
      if (mounted) {
        setState(() {
          _activeJob = null;
          _startingFreshJob = true;
          _editing = true;
          _step = 0;
        });
      }
      if (_page.hasClients) {
        _page.jumpToPage(0);
      }
      return;
    }

    if (widget.editActiveOnOpen && active != null) {
      if (_page.hasClients) {
        _page.jumpToPage(0);
      }
    }
  }

  ActiveWorkflowMode _workflowFromJob(
    JobSetup? job,
    ActiveWorkflowMode fallback,
  ) {
    final raw = (job?.workflow ?? '').trim().toLowerCase();
    if (raw == 'drillout') return ActiveWorkflowMode.drillout;
    if (raw == 'cleanout') return ActiveWorkflowMode.cleanout;
    return fallback;
  }

  void _scheduleAutoSave() {
    if (_loading || !_editing) {
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 550), () async {
      if (!_canAutoSave()) return;
      final currentEditing = _activeJob;
      if (currentEditing == null) return;

      setState(() {
        _autoSaving = true;
      });

      try {
        final draft = _activeWorkflowMode == ActiveWorkflowMode.production
            ? _buildJobFromForm()
            : _buildDrilloutJobFromForm();
        final safeDraft = draft.copyWith(
          id: currentEditing.id,
          status: currentEditing.status,
          startedAt: currentEditing.startedAt,
          endedAt: currentEditing.endedAt,
        );
        final saved = await _storage.updateActiveJob(safeDraft);
        if (!mounted) return;
        setState(() {
          _activeJob = saved;
          _autoSaving = false;
          _lastAutoSaveAt = DateTime.now();
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _autoSaving = false;
        });
      }
    });
  }

  bool _canAutoSave() {
    return mounted &&
        !_loading &&
        _editing &&
        !_startingFreshJob &&
        _activeJob != null;
  }

  String _autoSaveStatusText() {
    if (_autoSaving) return 'Saving...';
    final savedAt = _lastAutoSaveAt;
    if (savedAt == null) return 'Autosave ready';
    return 'Saved ${DateFormat('h:mm a').format(savedAt)}';
  }

  void _applyDrilloutSetupToForm(JobSetup job) {
    final setup = job.drilloutSetup;
    jobLatitude.text = _legacyString(
      setup['locationLatitude'],
      fallback: _legacyString(
        setup['gpsLatitude'],
        fallback: _legacyString(setup['latitude']),
      ),
    );
    jobLongitude.text = _legacyString(
      setup['locationLongitude'],
      fallback: _legacyString(
        setup['gpsLongitude'],
        fallback: _legacyString(setup['longitude']),
      ),
    );
    _drilloutWellName.text = _legacyString(
      setup['wellName'],
      fallback: job.primaryWell,
    );
    _drilloutManifoldPsi.text = _legacyString(setup['manifoldPsi']);
    _drilloutCasingPsi.text = _legacyString(setup['casingPsi']);
    _drilloutPumpPsi.text = _legacyString(setup['pumpPsi']);
    _drilloutRateOverride.text = _legacyString(setup['rateOverride']);
    _drilloutSurfaceTotalFluid.text = _legacyString(setup['surfaceTotalFluid']);
    _drilloutWaterHauled.text = _legacyString(setup['waterHauled']);
    _drilloutOilHauled.text = _legacyString(setup['oilHauled']);
    _drilloutPlugNumber.text = _legacyString(setup['plugNumber']);
    _drilloutStatus.text = _legacyString(setup['status']);
    _drilloutCoilDepth.text = _legacyString(setup['coilDepth']);

    _tankConfig = DrilloutTankConfiguration.fromDrilloutSetup(setup);

    _flowbackGauge.text = _legacyString(setup['flowbackGauge']);
    _waterTank1Gauge.text = _legacyString(setup['waterTank1Gauge']);
    _waterTank2Gauge.text = _legacyString(setup['waterTank2Gauge']);
    _sweepTankGauge.text = _legacyString(setup['sweepTankGauge']);
    flareEcdGasRateEnabled =
        _legacyBool(setup['flareEcdGasRateEnabled'], fallback: true);
    includeNotesSection =
        _legacyBool(setup['includeNotesSection'], fallback: true);
    gasRateSource = _normalizeGasRateSource(setup['gasRateSource']);

    if (_drilloutWellName.text.trim().isEmpty && job.primaryWell.isNotEmpty) {
      _drilloutWellName.text = job.primaryWell;
    }
  }

  String _legacyString(dynamic value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _legacyBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    return fallback;
  }

  String _normalizeGasRateSource(dynamic value) {
    final normalized = (value ?? '').toString().trim();
    if (normalized == _gasRateSourceInstantSpot) {
      return _gasRateSourceInstantSpot;
    }
    return _gasRateSourceAccumulation;
  }

  String _normalizeProductionFlowPath(
    dynamic value, {
    required String fallback,
  }) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized == _flowPathEcd) {
      return _flowPathEcd;
    }
    if (normalized == _flowPathFlare) {
      return _flowPathFlare;
    }
    return fallback;
  }

  String _inferLegacyProductionFlowPath({
    required int flareCount,
    required int ecdCount,
  }) {
    if (ecdCount > 0 && flareCount <= 0) {
      return _flowPathEcd;
    }
    return _flowPathFlare;
  }

  String _flowPathLabel(String value) {
    return value == _flowPathEcd ? 'ECD' : 'Flare';
  }

  List<String> _equipmentDisplayLabels(
    List<String> sourceSections, {
    required String flowPath,
  }) {
    final labels = <String>[];
    for (final section in sourceSections) {
      final normalized = section.trim();
      if (normalized.isEmpty) continue;
      if (normalized == 'FLARE / ECD') {
        final flowLabel = _flowPathLabel(flowPath);
        if (!labels.contains(flowLabel)) {
          labels.add(flowLabel);
        }
        continue;
      }
      if (!labels.contains(normalized)) {
        labels.add(normalized);
      }
    }
    return labels;
  }

  Map<String, String> _wellStatusesFromSetup(Map<String, dynamic> setup) {
    final raw = setup['wellStatuses'];
    if (raw is! Map) return <String, String>{};
    return raw.map(
      (key, value) => MapEntry(key.toString().trim(), value.toString().trim()),
    );
  }

  Map<String, String> _normalizedWellStatuses({
    required List<JobSetupWell> entries,
    required String activeWellId,
    required Map<String, String> source,
  }) {
    final result = <String, String>{};
    for (final entry in entries) {
      final status = (source[entry.id] ?? '').trim();
      if (entry.id == activeWellId) {
        result[entry.id] = _wellStatusActive;
      } else if (status == _wellStatusComplete) {
        result[entry.id] = _wellStatusComplete;
      } else {
        result[entry.id] = _wellStatusNotStarted;
      }
    }
    return result;
  }

  OperationsLogWorkflow _operationsWorkflowForJob(JobSetup job) {
    final workflow = job.workflow.trim().toLowerCase();
    if (workflow == OperationsLogWorkflow.cleanout.name) {
      return OperationsLogWorkflow.cleanout;
    }
    return OperationsLogWorkflow.drillout;
  }

  void _resetDrilloutSetupForNewJob() {
    final active = _activeJob;
    _drilloutWellName.text = active?.primaryWell ?? '';
    jobLatitude.clear();
    jobLongitude.clear();
    _drilloutManifoldPsi.clear();
    _drilloutCasingPsi.clear();
    _drilloutPumpPsi.clear();
    _drilloutRateOverride.clear();
    _drilloutSurfaceTotalFluid.clear();
    _drilloutWaterHauled.clear();
    _drilloutOilHauled.clear();
    _drilloutPlugNumber.clear();
    _drilloutStatus.clear();
    _drilloutCoilDepth.clear();
    _tankConfig = DrilloutTankConfiguration.defaults;
    _flowbackGauge.clear();
    _waterTank1Gauge.clear();
    _waterTank2Gauge.clear();
    _sweepTankGauge.clear();
    flareEcdGasRateEnabled = true;
    includeNotesSection = true;
    gasRateSource = _gasRateSourceAccumulation;
  }

  Map<String, dynamic> _buildDrilloutSetupPayload() {
    final payload = <String, dynamic>{
      'wellName': _drilloutWellName.text.trim(),
      'locationPad': padName.text.trim(),
      'locationLatitude': jobLatitude.text.trim(),
      'locationLongitude': jobLongitude.text.trim(),
      'manifoldPsi': _drilloutManifoldPsi.text.trim(),
      'casingPsi': _drilloutCasingPsi.text.trim(),
      'pumpPsi': _drilloutPumpPsi.text.trim(),
      'rateOverride': _drilloutRateOverride.text.trim(),
      'surfaceTotalFluid': _drilloutSurfaceTotalFluid.text.trim(),
      'waterHauled': _drilloutWaterHauled.text.trim(),
      'oilHauled': _drilloutOilHauled.text.trim(),
      'plugNumber': _drilloutPlugNumber.text.trim(),
      'status': _drilloutStatus.text.trim(),
      'coilDepth': _drilloutCoilDepth.text.trim(),
      'flareEcdGasRateEnabled': flareEcdGasRateEnabled,
      'includeNotesSection': includeNotesSection,
      'gasRateSource': gasRateSource,
      'tankConfigurationV1': _tankConfig.toJson(),
    };

    final roleGauges = <String, String>{
      ..._tankConfig.gaugesByRole,
      DrilloutTankCatalog.roleSandTank: _flowbackGauge.text.trim(),
      DrilloutTankCatalog.roleFlowback1: _waterTank1Gauge.text.trim(),
      DrilloutTankCatalog.roleFlowback2: _waterTank2Gauge.text.trim(),
      DrilloutTankCatalog.roleSweep1: _sweepTankGauge.text.trim(),
    };

    final configWithGauges = _tankConfig.copyWith(gaugesByRole: roleGauges);
    payload['tankConfigurationV1'] = configWithGauges.toJson();
    payload.addAll(configWithGauges.toLegacyCompatJson());
    return payload;
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
      _scheduleAutoSave();
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
    _scheduleAutoSave();
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
      _scheduleAutoSave();
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
    _scheduleAutoSave();
  }

  Future<bool> _confirmTankRoleReduction(List<String> removedRoleIds) async {
    bool hasData = false;
    for (final roleId in removedRoleIds) {
      if ((_tankConfig.gaugesByRole[roleId] ?? '').trim().isNotEmpty) {
        hasData = true;
        break;
      }
    }

    if (!hasData) {
      if (removedRoleIds.contains(DrilloutTankCatalog.roleFlowback3) &&
          _waterTank2Gauge.text.trim().isNotEmpty) {
        hasData = true;
      }
      if (removedRoleIds.contains(DrilloutTankCatalog.roleFlowback2) &&
          _waterTank1Gauge.text.trim().isNotEmpty) {
        hasData = true;
      }
      if (removedRoleIds.contains(DrilloutTankCatalog.roleSandTank) &&
          _flowbackGauge.text.trim().isNotEmpty) {
        hasData = true;
      }
      if (removedRoleIds.contains(DrilloutTankCatalog.roleSweep1) &&
          _sweepTankGauge.text.trim().isNotEmpty) {
        hasData = true;
      }
    }

    if (!hasData) return true;

    final labels = removedRoleIds
        .map((id) => DrilloutTankCatalog.roleById(id).label)
        .join(', ');
    final decision = await showDialog<bool>(
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
    return decision ?? false;
  }

  String _workflowStorageValue() {
    if (_activeWorkflowMode == ActiveWorkflowMode.drillout) {
      return 'drillout';
    }
    if (_activeWorkflowMode == ActiveWorkflowMode.cleanout) {
      return 'cleanout';
    }
    return 'production';
  }

  bool _validateDrilloutForm() {
    final missing = <String>[];
    if (company.trim().isEmpty) missing.add('Company');
    if (padName.text.trim().isEmpty) missing.add('Location / Pad');
    if (jobType == JobProfileDefaultsService.jobTypeMultiWellPad) {
      final namedWells = wells.where((well) => well.trim().isNotEmpty).toList();
      if (namedWells.isEmpty) {
        missing.add('At least one Well Name');
      }
    } else {
      if (_drilloutWellName.text.trim().isEmpty) missing.add('Well Name');
    }
    if (shift.trim().isEmpty) missing.add('Shift');
    if (missing.isEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Required: ${missing.join(', ')}')),
    );
    return false;
  }

  JobSetup _buildDrilloutJobFromForm() {
    if (jobType == JobProfileDefaultsService.jobTypeSingleWell) {
      _ensurePerWellCapacity(1);
      final singleWell = _drilloutWellName.text.trim();
      wells[0] = singleWell;
      leaseNames[0] = singleWell;
    }

    final normalizedPairs = <MapEntry<String, String>>[];
    final normalizedLeaseNames = <String>[];
    for (int i = 0; i < wells.length; i++) {
      final lease = i < leaseNames.length ? leaseNames[i].trim() : '';
      final preferredName = wells[i].trim();
      final name = JobSetup.resolveDisplayWellName(
        preferredWellName: preferredName,
        leaseName: lease,
        legacyWellName: preferredName,
      );
      if (name.isEmpty) continue;
      final id = i < wellIds.length && wellIds[i].trim().isNotEmpty
          ? wellIds[i].trim()
          : JobSetup.generateWellId();
      normalizedPairs.add(MapEntry(id, name));
      normalizedLeaseNames.add(lease);
    }

    final safePairs = jobType == JobProfileDefaultsService.jobTypeSingleWell
        ? (normalizedPairs.isEmpty
            ? const <MapEntry<String, String>>[]
            : <MapEntry<String, String>>[normalizedPairs.first])
        : normalizedPairs;
    final safeLeaseNames =
        jobType == JobProfileDefaultsService.jobTypeSingleWell
            ? (normalizedLeaseNames.isEmpty
                ? const <String>[]
                : <String>[normalizedLeaseNames.first])
            : normalizedLeaseNames;
    final safeWells = [for (final item in safePairs) item.value];
    final safeWellEntries = [
      for (final item in safePairs)
        JobSetupWell(
          id: item.key,
          name: item.value,
        ),
    ];

    final resolvedPrimaryWell =
        safeWells.isNotEmpty ? safeWells.first : _drilloutWellName.text.trim();
    _drilloutWellName.text = resolvedPrimaryWell;

    final existingActiveWellId =
        (_activeJob?.drilloutSetup['activeWellId'] as String? ?? '').trim();
    final resolvedActiveWellId = safeWellEntries.any(
      (entry) => entry.id == existingActiveWellId,
    )
        ? existingActiveWellId
        : (safeWellEntries.isEmpty ? '' : safeWellEntries.first.id);
    final existingStatuses = _wellStatusesFromSetup(
      _activeJob?.drilloutSetup ?? const <String, dynamic>{},
    );
    final normalizedStatuses = _normalizedWellStatuses(
      entries: safeWellEntries,
      activeWellId: resolvedActiveWellId,
      source: existingStatuses,
    );

    final mergedSetup =
        Map<String, dynamic>.from(_activeJob?.drilloutSetup ?? const {});
    mergedSetup['flareEcdGasRateEnabled'] = flareEcdGasRateEnabled;
    mergedSetup['includeNotesSection'] = includeNotesSection;
    mergedSetup['gasRateSource'] = gasRateSource;
    mergedSetup['productionFlowPath'] = productionFlowPath;
    mergedSetup['activeWellId'] = resolvedActiveWellId;
    mergedSetup['activeWellName'] = safeWellEntries
        .firstWhere(
          (entry) => entry.id == resolvedActiveWellId,
          orElse: () => const JobSetupWell(id: '', name: ''),
        )
        .name
        .trim();
    mergedSetup['wellStatuses'] = normalizedStatuses;
    if (jobType == JobProfileDefaultsService.jobTypeMultiWellPad) {
      final draftRows = <Map<String, String>>[];
      for (int i = 0; i < wells.length; i++) {
        final id = i < wellIds.length && wellIds[i].trim().isNotEmpty
            ? wellIds[i].trim()
            : JobSetup.generateWellId();
        draftRows.add(<String, String>{
          'id': id,
          'name': i < wells.length ? wells[i] : '',
          'lease': i < leaseNames.length ? leaseNames[i] : '',
        });
      }
      mergedSetup['draftMultiWellsV1'] = draftRows;
    } else {
      mergedSetup.remove('draftMultiWellsV1');
    }
    mergedSetup.addAll(_buildDrilloutSetupPayload());

    return JobSetup(
      company: company.trim(),
      workflow: _workflowStorageValue(),
      jobType: jobType,
      customer: safeWells.isEmpty ? '' : safeWells.first,
      padName: padName.text.trim(),
      notes: notes.text.trim(),
      leaseName: safeLeaseNames.isNotEmpty ? safeLeaseNames.first : '',
      leaseNames: safeLeaseNames,
      county: county.text.trim(),
      state: state.text.trim(),
      shift: shift,
      dateStarted: dateStarted.text.trim(),
      status: _activeJob?.status ?? 'active',
      id: _activeJob?.id ?? '',
      startedAt: _activeJob?.startedAt,
      endedAt: _activeJob?.endedAt,
      wells: safeWells,
      wellEntries: safeWellEntries,
      wellFieldKeys: const <String>[],
      activeEquipmentSections: const <String>[],
      selectedChemicals: const <String>[],
      drilloutSetup: mergedSetup,
    );
  }

  void _applyJobToForm(JobSetup job) {
    company = _profileDefaults.normalizeCompany(job.company);
    jobType = _profileDefaults.normalizeJobType(job.jobType);
    final defaults = _profileDefaults.profileForCompany(company);
    wellFieldKeys = job.wellFieldKeys.isEmpty
        ? List<String>.from(defaults.wellFieldKeys)
        : List<String>.from(job.wellFieldKeys);
    final legacySections = job.activeEquipmentSections.isEmpty
        ? <String>[
            if (job.vrus > 0) 'VRU',
            if (job.flares > 0 || job.ecds > 0) 'FLARE / ECD',
            if (job.transferPumps > 0) 'Transfer Pump',
          ]
        : List<String>.from(job.activeEquipmentSections);
    final normalizedSections = <String>[];
    final allowedSections = defaults.optionalSections.toSet();
    for (final section in legacySections) {
      final normalized = section.trim();
      final upper = section.trim().toUpperCase();
      if (allowedSections.contains(normalized)) {
        if (!normalizedSections.contains(normalized)) {
          normalizedSections.add(normalized);
        }
        continue;
      }
      if (upper.contains('FLARE')) {
        if (!normalizedSections.contains('FLARE / ECD')) {
          normalizedSections.add('FLARE / ECD');
        }
        continue;
      }
      if (upper.contains('ECD')) {
        if (!normalizedSections.contains('FLARE / ECD')) {
          normalizedSections.add('FLARE / ECD');
        }
        continue;
      }
      if (upper == 'NOTES') {
        includeNotesSection = true;
        continue;
      }
    }
    activeEquipmentSections = normalizedSections;
    selectedChemicals
      ..clear()
      ..addAll(job.selectedChemicals);
    final setup = job.drilloutSetup;
    includeNotesSection = _legacyBool(setup['includeNotesSection'],
        fallback: includeNotesSection);
    flareEcdGasRateEnabled =
        _legacyBool(setup['flareEcdGasRateEnabled'], fallback: true);
    gasRateSource = _normalizeGasRateSource(setup['gasRateSource']);
    productionFlowPath = _normalizeProductionFlowPath(
      setup['productionFlowPath'],
      fallback: _inferLegacyProductionFlowPath(
        flareCount: job.flares,
        ecdCount: job.ecds,
      ),
    );
    shift = job.shift;
    padName.text = job.padName;
    notes.text = job.notes;
    leaseName.text = job.leaseName;
    county.text = job.county;
    state.text = job.state;
    dateStarted.text = job.dateStarted.trim().isEmpty
        ? DateFormat('MM/dd/yyyy').format(DateTime.now())
        : job.dateStarted;
    final draftRows = _draftMultiWellsFromSetup(setup);
    if (jobType == JobProfileDefaultsService.jobTypeMultiWellPad &&
        draftRows.isNotEmpty) {
      wells
        ..clear()
        ..addAll(draftRows.map((row) => row['name'] ?? ''));
      wellIds
        ..clear()
        ..addAll(draftRows.map((row) {
          final rawId = (row['id'] ?? '').trim();
          return rawId.isEmpty ? JobSetup.generateWellId() : rawId;
        }));
      leaseNames
        ..clear()
        ..addAll(draftRows.map((row) => row['lease'] ?? ''));
    } else {
      wells
        ..clear()
        ..addAll(job.wells);
      wellIds
        ..clear()
        ..addAll(job.wellIds);
      final resolvedLeases = job.resolvedLeaseNames;
      leaseNames
        ..clear()
        ..addAll(resolvedLeases);
    }
    _ensurePerWellCapacity(wells.length);
    for (int i = 0; i < wells.length; i++) {
      final lease = i < leaseNames.length ? leaseNames[i].trim() : '';
      final well = wells[i].trim();
      if ((well.isEmpty || JobSetup.isPlaceholderWellName(well)) &&
          lease.isNotEmpty) {
        wells[i] = lease;
      }
      wellNameManuallyEdited[i] = false;
      _syncWellNameFromLease(i);
    }

    if (jobType == JobProfileDefaultsService.jobTypeSingleWell &&
        wells.isEmpty &&
        leaseName.text.trim().isNotEmpty) {
      _ensurePerWellCapacity(1);
      leaseNames[0] = leaseName.text.trim();
      _syncWellNameFromLease(0, force: true);
    }

    if (jobType == JobProfileDefaultsService.jobTypeSingleWell &&
        wells.length > 1) {
      _ensurePerWellCapacity(1);
    }
    sandSeparators.text = job.sandSeparators.toString();
    plugCatchers.text = job.plugCatchers.toString();
    chokeManifolds.text = job.chokeManifolds.toString();
    lineHeaters.text = job.lineHeaters.toString();
    testUnits.text = job.testUnits.toString();
    ecds.text = job.ecds.toString();
    vrus.text = job.vrus.toString();
    flares.text = job.flares.toString();
    transferPumps.text = job.transferPumps.toString();
    oilTanks.text = job.oilTanks.toString();
    oilTankCapacity.text = job.oilTankCapacity;
    waterTanks.text = job.waterTanks.toString();
    waterTankCapacity.text = job.waterTankCapacity;
    productionTankFactor.text = job.productionTankFactor;
  }

  void _resetFormForNewJob() {
    final globalCompany = _activeCompanyService.activeCompany.value.trim();
    company = globalCompany.isEmpty ? 'Mach Energy' : globalCompany;
    jobType = JobProfileDefaultsService.jobTypeSingleWell;
    final defaults = _profileDefaults.profileForCompany(company);
    wellFieldKeys = List<String>.from(defaults.wellFieldKeys);
    activeEquipmentSections = List<String>.from(defaults.defaultActiveSections);
    includeNotesSection = true;
    flareEcdGasRateEnabled = true;
    gasRateSource = _gasRateSourceAccumulation;
    productionFlowPath = _flowPathFlare;
    selectedChemicals
      ..clear()
      ..addAll(const <String>[]);
    shift = 'Day';
    padName.clear();
    notes.clear();
    leaseName.clear();
    county.clear();
    state.text = 'Oklahoma';
    jobLatitude.clear();
    jobLongitude.clear();
    dateStarted.text = DateFormat('MM/dd/yyyy').format(DateTime.now());
    wells.clear();
    wellIds.clear();
    leaseNames.clear();
    wellNameManuallyEdited.clear();
    _ensurePerWellCapacity(1);
    sandSeparators.text = '2';
    plugCatchers.text = '1';
    chokeManifolds.text = '1';
    lineHeaters.text = '1';
    testUnits.text = '1';
    ecds.text = '0';
    vrus.text = '0';
    flares.text = '0';
    transferPumps.text = '0';
    oilTanks.text = '4';
    oilTankCapacity.text = '400';
    waterTanks.text = '6';
    waterTankCapacity.text = '400';
    productionTankFactor.text = '1.67';
  }

  JobSetup _buildJobFromForm() {
    final singleLeaseText = leaseName.text.trim();
    if (jobType == JobProfileDefaultsService.jobTypeSingleWell) {
      _ensurePerWellCapacity(1);
      if (leaseNames[0].trim().isEmpty && singleLeaseText.isNotEmpty) {
        leaseNames[0] = singleLeaseText;
      }
      _syncWellNameFromLease(0);
    }

    final normalizedPairs = <MapEntry<String, String>>[];
    final normalizedLeaseNames = <String>[];
    for (int i = 0; i < wells.length; i++) {
      final lease = i < leaseNames.length ? leaseNames[i].trim() : '';
      final preferredName = wells[i].trim();
      final name = JobSetup.resolveDisplayWellName(
        preferredWellName: preferredName,
        leaseName: lease,
        legacyWellName: preferredName,
      );
      if (name.isEmpty) continue;
      final id = i < wellIds.length && wellIds[i].trim().isNotEmpty
          ? wellIds[i].trim()
          : JobSetup.generateWellId();
      normalizedPairs.add(MapEntry(id, name));
      normalizedLeaseNames.add(lease);
    }
    final safePairs = jobType == JobProfileDefaultsService.jobTypeSingleWell
        ? (normalizedPairs.isEmpty
            ? const <MapEntry<String, String>>[]
            : <MapEntry<String, String>>[normalizedPairs.first])
        : normalizedPairs;
    final safeLeaseNames =
        jobType == JobProfileDefaultsService.jobTypeSingleWell
            ? (normalizedLeaseNames.isEmpty
                ? const <String>[]
                : <String>[normalizedLeaseNames.first])
            : normalizedLeaseNames;
    final safeWells = [for (final item in safePairs) item.value];
    final safeWellEntries = [
      for (final item in safePairs)
        JobSetupWell(
          id: item.key,
          name: item.value,
        ),
    ];
    final existingActiveWellId =
        (_activeJob?.drilloutSetup['activeWellId'] as String? ?? '').trim();
    final resolvedActiveWellId = safeWellEntries.any(
      (entry) => entry.id == existingActiveWellId,
    )
        ? existingActiveWellId
        : (safeWellEntries.isEmpty ? '' : safeWellEntries.first.id);
    final existingStatuses = _wellStatusesFromSetup(
      _activeJob?.drilloutSetup ?? const <String, dynamic>{},
    );
    final normalizedStatuses = _normalizedWellStatuses(
      entries: safeWellEntries,
      activeWellId: resolvedActiveWellId,
      source: existingStatuses,
    );
    final mergedSetup =
        Map<String, dynamic>.from(_activeJob?.drilloutSetup ?? const {});
    mergedSetup['locationLatitude'] = jobLatitude.text.trim();
    mergedSetup['locationLongitude'] = jobLongitude.text.trim();
    mergedSetup['flareEcdGasRateEnabled'] = flareEcdGasRateEnabled;
    mergedSetup['includeNotesSection'] = includeNotesSection;
    mergedSetup['gasRateSource'] = gasRateSource;
    mergedSetup['activeWellId'] = resolvedActiveWellId;
    mergedSetup['activeWellName'] = safeWellEntries
        .firstWhere(
          (entry) => entry.id == resolvedActiveWellId,
          orElse: () => const JobSetupWell(id: '', name: ''),
        )
        .name
        .trim();
    mergedSetup['wellStatuses'] = normalizedStatuses;
    if (jobType == JobProfileDefaultsService.jobTypeMultiWellPad) {
      final draftRows = <Map<String, String>>[];
      for (int i = 0; i < wells.length; i++) {
        final id = i < wellIds.length && wellIds[i].trim().isNotEmpty
            ? wellIds[i].trim()
            : JobSetup.generateWellId();
        draftRows.add(<String, String>{
          'id': id,
          'name': i < wells.length ? wells[i] : '',
          'lease': i < leaseNames.length ? leaseNames[i] : '',
        });
      }
      mergedSetup['draftMultiWellsV1'] = draftRows;
    } else {
      mergedSetup.remove('draftMultiWellsV1');
    }

    var nextEcds = _i(ecds);
    var nextFlares = _i(flares);
    if (activeEquipmentSections.contains('FLARE / ECD')) {
      if (productionFlowPath == _flowPathEcd) {
        if (nextEcds <= 0) nextEcds = 1;
        nextFlares = 0;
      } else {
        if (nextFlares <= 0) nextFlares = 1;
        nextEcds = 0;
      }
    } else {
      nextEcds = 0;
      nextFlares = 0;
    }

    final nextVrus = activeEquipmentSections.contains('VRU')
        ? (_i(vrus) <= 0 ? 1 : _i(vrus))
        : 0;
    final nextTransferPumps = activeEquipmentSections.contains('Transfer Pump')
        ? (_i(transferPumps) <= 0 ? 1 : _i(transferPumps))
        : 0;

    return JobSetup(
      company: company,
      workflow: _workflowStorageValue(),
      jobType: jobType,
      customer: safeWells.isEmpty ? '' : safeWells.first,
      padName: padName.text.trim(),
      notes: notes.text.trim(),
      leaseName:
          safeLeaseNames.isNotEmpty ? safeLeaseNames.first : singleLeaseText,
      leaseNames: safeLeaseNames,
      county: county.text.trim(),
      state: state.text.trim(),
      shift: shift,
      dateStarted: dateStarted.text.trim(),
      status: _activeJob?.status ?? 'active',
      id: _activeJob?.id ?? '',
      startedAt: _activeJob?.startedAt,
      endedAt: _activeJob?.endedAt,
      wells: safeWells,
      wellEntries: safeWellEntries,
      wellFieldKeys: List<String>.from(wellFieldKeys),
      activeEquipmentSections: List<String>.from(activeEquipmentSections),
      sandSeparators: _i(sandSeparators),
      plugCatchers: _i(plugCatchers),
      chokeManifolds: _i(chokeManifolds),
      lineHeaters: _i(lineHeaters),
      testUnits: _i(testUnits),
      ecds: nextEcds,
      vrus: nextVrus,
      flares: nextFlares,
      transferPumps: nextTransferPumps,
      oilTanks: _i(oilTanks),
      oilTankCapacity: oilTankCapacity.text.trim(),
      waterTanks: _i(waterTanks),
      waterTankCapacity: waterTankCapacity.text.trim(),
      productionTankFactor: productionTankFactor.text.trim().isEmpty
          ? '1.67'
          : productionTankFactor.text.trim(),
      selectedChemicals: List<String>.from(selectedChemicals),
      drilloutSetup: mergedSetup,
    );
  }

  void _next() {
    if (_step >= 4) return;
    setState(() => _step++);
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _backStep() {
    if (_step == 0) return;
    setState(() => _step--);
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  bool get _isMultiWellPad =>
      jobType == JobProfileDefaultsService.jobTypeMultiWellPad;

  void _setMultiWellPad(bool enabled) {
    setState(() {
      jobType = enabled
          ? JobProfileDefaultsService.jobTypeMultiWellPad
          : JobProfileDefaultsService.jobTypeSingleWell;
      if (enabled) {
        if (wells.isEmpty) {
          _ensurePerWellCapacity(1);
        }
      } else {
        _ensurePerWellCapacity(1);
      }
    });
    _scheduleAutoSave();
  }

  void _addMultiWellRow() {
    if (!_isMultiWellPad) return;
    int nextIndex = wells.length;
    setState(() {
      _ensurePerWellCapacity(wells.length + 1);
      nextIndex = wells.length - 1;
    });
    _focusAndRevealWellAt(nextIndex);
    _scheduleAutoSave();
  }

  void _removeMultiWellRow(int index) {
    if (index < 0 || index >= wells.length) return;
    if (wells.length <= 1) return;
    setState(() {
      wells.removeAt(index);
      if (index < wellIds.length) wellIds.removeAt(index);
      if (index < leaseNames.length) leaseNames.removeAt(index);
      if (index < wellNameManuallyEdited.length) {
        wellNameManuallyEdited.removeAt(index);
      }
      if (index < _wellNameControllers.length) {
        _wellNameControllers.removeAt(index).dispose();
      }
      if (index < _wellNameFocusNodes.length) {
        _wellNameFocusNodes.removeAt(index).dispose();
      }
      _ensurePerWellCapacity(wells.length);
    });
    _scheduleAutoSave();
  }

  String _wellStatusLabel(String status) {
    switch (status.trim()) {
      case _wellStatusActive:
        return 'Active';
      case _wellStatusComplete:
        return 'Complete';
      default:
        return 'Not Started';
    }
  }

  Future<void> _switchActiveWell(String nextWellId) async {
    final active = _activeJob;
    if (active == null) return;
    final currentWellId = active.activeWellId;
    if (nextWellId.trim().isEmpty || nextWellId == currentWellId) return;

    final entries = active.resolvedWellEntries;
    final currentName = entries
        .firstWhere(
          (entry) => entry.id == currentWellId,
          orElse: () => const JobSetupWell(id: '', name: ''),
        )
        .name
        .trim();
    final nextName = entries
        .firstWhere(
          (entry) => entry.id == nextWellId,
          orElse: () => const JobSetupWell(id: '', name: ''),
        )
        .name
        .trim();
    if (nextName.isEmpty) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Switch Active Well?'),
            content: Text(
              'Switch from ${currentName.isEmpty ? 'current well' : currentName} to $nextName? The current well session will be finalized and the next well session will start.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Switch Well'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final workflow = _operationsWorkflowForJob(active);
    final now = DateTime.now();
    final statuses = _wellStatusesFromSetup(active.drilloutSetup);
    for (final entry in entries) {
      statuses.putIfAbsent(entry.id, () => _wellStatusNotStarted);
    }
    if (currentWellId.isNotEmpty && currentWellId != nextWellId) {
      statuses[currentWellId] = _wellStatusComplete;
    }
    statuses[nextWellId] = _wellStatusActive;

    final updatedSetup = Map<String, dynamic>.from(active.drilloutSetup)
      ..['activeWellId'] = nextWellId
      ..['activeWellName'] = nextName
      ..['wellStatuses'] = statuses;

    final updatedJob = active.copyWith(drilloutSetup: updatedSetup);

    final existingEntries = await _operationsLogService.loadEntries(
      workflow: workflow,
      jobId: active.id,
    );
    final sessionMarkers = <OperationsLogEntry>[];
    if (currentWellId.isNotEmpty) {
      sessionMarkers.add(await _operationsLogService.createLocalEntry(
        workflow: workflow,
        jobId: active.id,
        wellId: currentWellId,
        wellName: currentName,
        readingTimestamp: now,
        entryType: 'wellSessionFinalized',
        generatedText: 'Well session finalized before switching to $nextName.',
        notes: 'Well session finalized before switching to $nextName.',
      ));
    }
    sessionMarkers.add(await _operationsLogService.createLocalEntry(
      workflow: workflow,
      jobId: active.id,
      wellId: nextWellId,
      wellName: nextName,
      readingTimestamp: now,
      entryType: 'wellSessionStarted',
      generatedText: 'Well session started for $nextName.',
      notes: 'Well session started for $nextName.',
    ));

    await _operationsLogService.saveEntries(
      workflow: workflow,
      jobId: active.id,
      entries: [...existingEntries, ...sessionMarkers],
    );

    await _historyService.archiveCurrentJobOrShift();
    await _productionShiftService.archiveActiveShift();
    await _productionShiftService.clearActiveShift();
    final saved = await _storage.updateActiveJob(updatedJob);

    if (!mounted) return;
    setState(() {
      _activeJob = saved;
      _lastAutoSaveAt = DateTime.now();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Active well switched to $nextName')),
    );
  }

  void _startJobSetup() {
    _workflowModeService.setMode(_activeWorkflowMode);
    if (_activeWorkflowMode == ActiveWorkflowMode.production) {
      _resetFormForNewJob();
    } else {
      _resetDrilloutSetupForNewJob();
    }
    setState(() {
      _activeJob = null;
      _startingFreshJob = true;
      _editing = true;
      _lastAutoSaveAt = null;
      _step = 0;
    });
    if (_page.hasClients) {
      _page.jumpToPage(0);
    }
  }

  void _setStartJobWorkflowMode(ActiveWorkflowMode mode) {
    if (_activeWorkflowMode == mode) return;
    setState(() {
      _activeWorkflowMode = mode;
      _step = 0;
    });
    if (mode == ActiveWorkflowMode.production) {
      _resetFormForNewJob();
      if (_page.hasClients) {
        _page.jumpToPage(0);
      }
    } else {
      _resetDrilloutSetupForNewJob();
    }
    _workflowModeService.setMode(mode);
  }

  Widget _startJobWorkflowSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Job Type',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ActiveWorkflowMode>(
              segments: const [
                ButtonSegment<ActiveWorkflowMode>(
                  value: ActiveWorkflowMode.production,
                  label: Text('Production'),
                ),
                ButtonSegment<ActiveWorkflowMode>(
                  value: ActiveWorkflowMode.drillout,
                  label: Text('Drillout'),
                ),
                ButtonSegment<ActiveWorkflowMode>(
                  value: ActiveWorkflowMode.cleanout,
                  label: Text('Cleanout'),
                ),
              ],
              selected: {_activeWorkflowMode},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                _setStartJobWorkflowMode(selection.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editActiveJob() {
    final active = _activeJob;
    if (active == null) return;

    if (_activeWorkflowMode == ActiveWorkflowMode.production) {
      _applyJobToForm(active);
    } else {
      _applyDrilloutSetupToForm(active);
    }
    setState(() {
      _startingFreshJob = false;
      _editing = true;
      _lastAutoSaveAt = null;
      _step = 0;
    });
    if (_page.hasClients) {
      _page.jumpToPage(0);
    }
  }

  Future<void> _save() async {
    if (_activeWorkflowMode != ActiveWorkflowMode.production) {
      if (!_validateDrilloutForm()) return;
    }
    final isStartingNewJob = _startingFreshJob || _activeJob == null;
    final job = _activeWorkflowMode == ActiveWorkflowMode.production
        ? _buildJobFromForm()
        : _buildDrilloutJobFromForm();
    final saved = isStartingNewJob
        ? await _storage.saveActiveJob(job)
        : await _storage.updateActiveJob(job);

    if (_activeWorkflowMode != ActiveWorkflowMode.production) {
      await _workflowModeService.setMode(_activeWorkflowMode);
    }

    if (!mounted) return;
    setState(() {
      _activeJob = saved;
      _startingFreshJob = false;
      _editing = false;
      _lastAutoSaveAt = DateTime.now();
      _step = 0;
    });
    if (_page.hasClients) {
      _page.jumpToPage(0);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            isStartingNewJob ? 'Active job started' : 'Active job updated'),
      ),
    );
  }

  Future<void> _confirmEndJob() async {
    final active = _activeJob;
    if (active == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('End Active Job?'),
            content: Text(
              'This will mark ${active.primaryWell.isEmpty ? 'the current job' : active.primaryWell} as ended and remove it from Active Job.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('End Job'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final ended = await _storage.endActiveJob();
    if (!mounted || ended == null) return;

    _applyJobToForm(ended);
    setState(() {
      _activeJob = null;
      _startingFreshJob = false;
      _editing = false;
      _step = 0;
    });

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Widget _navButtons({bool finish = false}) {
    return Row(
      children: [
        if (_step > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _backStep,
              child: const Text('Back'),
            ),
          ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: finish ? _save : _next,
            child: Text(
              finish
                  ? (_startingFreshJob ? 'Start Job' : 'Update Active Job')
                  : 'Next',
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) return 'Not started';
    return DateFormat('MM/dd/yyyy h:mm a').format(value);
  }

  String _displayValue(String value, {String fallback = 'Not entered'}) {
    return value.trim().isEmpty ? fallback : value.trim();
  }

  String _productionJobTypeLabel(String value) {
    return value == JobProfileDefaultsService.jobTypeMultiWellPad
        ? 'Multi-Well Production'
        : 'Single Well';
  }

  List<String> _configuredWellNamesForReview() {
    final names = <String>[];
    for (int i = 0; i < wells.length; i++) {
      final lease = i < leaseNames.length ? leaseNames[i].trim() : '';
      final preferred = wells[i].trim();
      final resolved = JobSetup.resolveDisplayWellName(
        preferredWellName: preferred,
        leaseName: lease,
        legacyWellName: preferred,
      );
      if (resolved.isNotEmpty && !names.contains(resolved)) {
        names.add(resolved);
      }
    }
    return names;
  }

  Widget _jobReviewSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _buildProductionJobReviewCard() {
    final configuredWells = _configuredWellNamesForReview();
    final isMultiWell = _isMultiWellPad;
    final equipmentLabels = _equipmentDisplayLabels(
      activeEquipmentSections,
      flowPath: productionFlowPath,
    );
    const productionDataFields = <String>[
      'Choke',
      'TBG',
      'CSG',
      'ICP',
      'Gas Static',
      'Gas Differential',
      'Gas Temperature',
      'Gas Rate',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Job Review',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            _jobReviewSection('CUSTOMER', [
              Text(_displayValue(company, fallback: 'None')),
            ]),
            _jobReviewSection('WORKFLOW', const [
              Text('Production'),
            ]),
            _jobReviewSection('JOB TYPE', [
              Text(_productionJobTypeLabel(jobType)),
            ]),
            if (isMultiWell)
              _jobReviewSection('PAD', [
                Text(_displayValue(padName.text, fallback: 'Not entered')),
              ]),
            _jobReviewSection('WELLS', [
              Text('${configuredWells.length} configured well(s)'),
              const SizedBox(height: 4),
              if (configuredWells.isEmpty)
                const Text('None')
              else
                for (final well in configuredWells) Text('• $well'),
            ]),
            _jobReviewSection('PRODUCTION DATA', [
              for (final field in productionDataFields) Text('• $field'),
            ]),
            _jobReviewSection('TANK SETUP', [
              if (configuredWells.isEmpty)
                const Text('No configured wells')
              else
                for (int i = 0; i < configuredWells.length; i++) ...[
                  Text(
                    configuredWells[i],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${oilTanks.text.trim().isEmpty ? '0' : oilTanks.text.trim()} Oil Tanks (${_displayValue(oilTankCapacity.text, fallback: '0')} bbl)',
                  ),
                  Text(
                    '${waterTanks.text.trim().isEmpty ? '0' : waterTanks.text.trim()} Water Tanks (${_displayValue(waterTankCapacity.text, fallback: '0')} bbl)',
                  ),
                  if (i < configuredWells.length - 1) const SizedBox(height: 8),
                ],
            ]),
            _jobReviewSection('EQUIPMENT', [
              if (equipmentLabels.isEmpty)
                const Text('None')
              else
                for (final item in equipmentLabels) Text('• $item'),
            ]),
            _jobReviewSection('PROP / SAND', const [
              Text('• Amount'),
              Text('• Optional Rate'),
            ]),
            _jobReviewSection('NOTES', [
              Text(_displayValue(notes.text, fallback: 'Not entered')),
            ]),
            _jobReviewSection('CHEMICALS', [
              if (selectedChemicals.isEmpty)
                const Text('None')
              else
                for (final chemical in selectedChemicals) Text('• $chemical'),
            ]),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProductionSetupPages() {
    return [
      _StepPage(title: '1. Job Information', children: [
        DropdownButtonFormField<String>(
          key: const Key('job-info-company-field'),
          initialValue:
              _companyOptions().contains(company) ? company.trim() : null,
          decoration: const InputDecoration(labelText: 'Company'),
          items: _companyOptions()
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            _setCompany(value);
          },
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _isMultiWellPad,
          title: const Text('Multi-Well Pad'),
          subtitle: const Text(
              'Enable when this job includes multiple wells on the same pad.'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          onChanged: (enabled) => _setMultiWellPad(enabled ?? false),
        ),
        const SizedBox(height: 10),
        if (!_isMultiWellPad)
          TextField(
            controller: leaseName,
            decoration: const InputDecoration(labelText: 'Well Name'),
            onChanged: (value) {
              _ensurePerWellCapacity(1);
              _setLeaseNameAt(0, value);
              _setWellNameAt(0, value);
              _scheduleAutoSave();
            },
          )
        else ...[
          TextField(
            controller: padName,
            decoration: const InputDecoration(labelText: 'Pad Name'),
            onChanged: (_) => _scheduleAutoSave(),
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Wells',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < wells.length; i++) ...[
            Row(
              key: _wellRowKeys[wellIds[i]],
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('job-info-well-${wellIds[i]}'),
                    controller: _wellNameControllerAt(i),
                    focusNode: _wellNameFocusNodeAt(i),
                    decoration:
                        InputDecoration(labelText: 'Well ${i + 1} Name'),
                    onChanged: (value) {
                      _setWellNameAt(i, value);
                      _setLeaseNameAt(i, value);
                      _scheduleAutoSave();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed:
                      wells.length > 1 ? () => _removeMultiWellRow(i) : null,
                  tooltip: 'Remove Well',
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addMultiWellRow,
              icon: const Icon(Icons.add),
              label: const Text('Add Well'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _navButtons(),
      ]),
      _StepPage(title: '2. Production Data', children: [
        if (!_isMultiWellPad)
          TextField(
            controller: padName,
            decoration: const InputDecoration(labelText: 'Pad Name (Optional)'),
            onChanged: (_) => _scheduleAutoSave(),
          ),
        if (!_isMultiWellPad) const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: shift,
          decoration: const InputDecoration(labelText: 'Shift'),
          items: const [
            DropdownMenuItem(value: 'Day', child: Text('Day')),
            DropdownMenuItem(value: 'Night', child: Text('Night')),
          ],
          onChanged: (value) {
            setState(() => shift = value ?? 'Day');
            _scheduleAutoSave();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: dateStarted,
          decoration: const InputDecoration(labelText: 'Date'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: county,
          decoration: const InputDecoration(labelText: 'County'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: jobLatitude,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: jobLongitude,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _gpsFilling ? null : _fillCoordinatesFromCurrentLocation,
            icon: _gpsFilling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(_gpsFilling ? 'Capturing GPS...' : 'Use Current GPS'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: state,
          decoration: const InputDecoration(labelText: 'State'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        const SizedBox(height: 12),
        _countField('Oil Tanks', oilTanks),
        WwNumberField(
          label: 'Oil Tank Capacity (per well)',
          controller: oilTankCapacity,
          onChanged: (_) => _scheduleAutoSave(),
        ),
        const SizedBox(height: 10),
        _countField('Water Tanks', waterTanks),
        WwNumberField(
          label: 'Water Tank Capacity (per well)',
          controller: waterTankCapacity,
          onChanged: (_) => _scheduleAutoSave(),
        ),
        const SizedBox(height: 10),
        WwNumberField(
          label: 'Production Tank Factor (BBL/In)',
          controller: productionTankFactor,
          allowDecimal: true,
          onChanged: (_) => _scheduleAutoSave(),
        ),
        const SizedBox(height: 24),
        _navButtons(),
      ]),
      _StepPage(title: '3. Active Equipment', children: [
        ..._profileDefaults.profileForCompany(company).optionalSections.map(
              (section) => CheckboxListTile(
                value: activeEquipmentSections.contains(section),
                title: Text(section),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: (enabled) {
                  setState(() {
                    if (enabled ?? false) {
                      if (!activeEquipmentSections.contains(section)) {
                        activeEquipmentSections.add(section);
                      }
                    } else {
                      activeEquipmentSections.remove(section);
                    }
                  });
                  _scheduleAutoSave();
                },
              ),
            ),
        if (activeEquipmentSections.contains('FLARE / ECD')) ...[
          const SizedBox(height: 8),
          const Text(
            'Flare / ECD Configuration',
            style: TextStyle(
              color: Color(0xFFCDA56A),
              fontWeight: FontWeight.w700,
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text('Flare'),
                selected: productionFlowPath == _flowPathFlare,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    productionFlowPath = _flowPathFlare;
                  });
                  _scheduleAutoSave();
                },
              ),
              ChoiceChip(
                label: const Text('ECD'),
                selected: productionFlowPath == _flowPathEcd,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    productionFlowPath = _flowPathEcd;
                  });
                  _scheduleAutoSave();
                },
              ),
            ],
          ),
          CheckboxListTile(
            value: flareEcdGasRateEnabled,
            title: const Text('Include Gas Rate'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            onChanged: (enabled) {
              setState(() {
                flareEcdGasRateEnabled = enabled ?? true;
              });
              _scheduleAutoSave();
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: gasRateSource,
            decoration: const InputDecoration(labelText: 'Gas Rate Source'),
            items: const [
              DropdownMenuItem(
                value: _gasRateSourceInstantSpot,
                child: Text('Instant Spot Rate'),
              ),
              DropdownMenuItem(
                value: _gasRateSourceAccumulation,
                child: Text('Gas Accumulation'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                gasRateSource = value;
              });
              _scheduleAutoSave();
            },
          ),
        ],
        const SizedBox(height: 24),
        _navButtons(),
      ]),
      _StepPage(title: '4. Chemicals', children: [
        ...JobSetup.chemicalOptions.map(
          (chemical) => CheckboxListTile(
            value: selectedChemicals.contains(chemical),
            title: Text(chemical),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            onChanged: (enabled) {
              setState(() {
                if (enabled ?? false) {
                  if (!selectedChemicals.contains(chemical)) {
                    selectedChemicals.add(chemical);
                  }
                } else {
                  selectedChemicals.remove(chemical);
                }
              });
              _scheduleAutoSave();
            },
          ),
        ),
        const SizedBox(height: 24),
        _navButtons(),
      ]),
      _StepPage(title: '5. Job Review', children: [
        _buildProductionJobReviewCard(),
        const SizedBox(height: 24),
        _navButtons(finish: true),
      ]),
    ];
  }

  Widget _buildOverviewValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 17)),
        ],
      ),
    );
  }

  Widget _buildNoActiveJobView() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No Active Job',
                  style: TextStyle(
                    color: Color(0xFFCDA56A),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Start a job to keep the current company, pad, well, shift, and notes active on this device.',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 16),
                _startJobWorkflowSelector(),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startJobSetup,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Job'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveJobView(JobSetup job) {
    final defaults = _profileDefaults.profileForCompany(job.company);
    final isProduction = _activeWorkflowMode == ActiveWorkflowMode.production;
    final resolvedWells = job.resolvedWellNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final configuredWellCount = resolvedWells.length;
    final configuredWells = configuredWellCount == 0
        ? const <String>['Not entered']
        : List<String>.from(resolvedWells);
    final productionFlowPath = _normalizeProductionFlowPath(
      job.drilloutSetup['productionFlowPath'],
      fallback: _inferLegacyProductionFlowPath(
        flareCount: job.flares,
        ecdCount: job.ecds,
      ),
    );
    final productionEquipment = _equipmentDisplayLabels(
      job.activeEquipmentSections.isEmpty
          ? defaults.defaultActiveSections
          : job.activeEquipmentSections,
      flowPath: productionFlowPath,
    );
    final productionStatus = job.status.trim().isEmpty
        ? 'Active'
        : '${job.status.trim()[0].toUpperCase()}${job.status.trim().substring(1)}';

    if (isProduction) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Active Job',
                          style: TextStyle(
                            color: Color(0xFFCDA56A),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Chip(label: Text(job.status.toUpperCase())),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildOverviewValue('Customer', _displayValue(job.company)),
                  _buildOverviewValue('Workflow', 'Production'),
                  _buildOverviewValue('Pad', _displayValue(job.padName)),
                  _buildOverviewValue(
                    'Configured Wells',
                    '$configuredWellCount well(s): ${configuredWells.join(', ')}',
                  ),
                  _buildOverviewValue('Shift', _displayValue(job.shift)),
                  _buildOverviewValue(
                    'Equipment',
                    productionEquipment.isEmpty
                        ? 'None'
                        : productionEquipment.join(', '),
                  ),
                  _buildOverviewValue(
                    'Gas Rate Source',
                    _normalizeGasRateSource(
                                job.drilloutSetup['gasRateSource']) ==
                            _gasRateSourceInstantSpot
                        ? 'Instant Spot Rate'
                        : 'Gas Accumulation',
                  ),
                  _buildOverviewValue(
                      'Started', _formatTimestamp(job.startedAt)),
                  _buildOverviewValue('Production Status', productionStatus),
                  _buildOverviewValue('Notes', _displayValue(job.notes)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _editActiveJob,
                      icon: const Icon(Icons.edit),
                      label: const Text('Update Active Job'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _confirmEndJob,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('End Job'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final bestIdentifier = job.primaryWell.trim().isNotEmpty
        ? job.primaryWell.trim()
        : (job.padName.trim().isNotEmpty ? job.padName.trim() : '-');
    final resolvedWellEntries = job.resolvedWellEntries;
    final statuses = _normalizedWellStatuses(
      entries: resolvedWellEntries,
      activeWellId: job.activeWellId,
      source: job.wellStatuses,
    );

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Active Job',
                        style: TextStyle(
                          color: Color(0xFFCDA56A),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(label: Text(job.status.toUpperCase())),
                  ],
                ),
                const SizedBox(height: 16),
                _buildOverviewValue('Company', _displayValue(job.company)),
                _buildOverviewValue(
                    'Workflow',
                    _workflowStorageValue()[0].toUpperCase() +
                        _workflowStorageValue().substring(1)),
                _buildOverviewValue(
                    'Location / Pad', _displayValue(job.padName)),
                _buildOverviewValue('Well Name', _displayValue(bestIdentifier)),
                if (resolvedWellEntries.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Well Sessions',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final well in resolvedWellEntries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              well.name.trim().isEmpty
                                  ? 'Unnamed Well'
                                  : well.name.trim(),
                            ),
                          ),
                          Chip(
                            label: Text(
                              _wellStatusLabel(
                                statuses[well.id] ?? _wellStatusNotStarted,
                              ),
                            ),
                          ),
                          if (well.id != job.activeWellId)
                            TextButton(
                              onPressed: () => _switchActiveWell(well.id),
                              child: const Text('Switch'),
                            ),
                        ],
                      ),
                    ),
                ],
                _buildOverviewValue('Shift', _displayValue(job.shift)),
                _buildOverviewValue('Date', _displayValue(job.dateStarted)),
                _buildOverviewValue('Started', _formatTimestamp(job.startedAt)),
                _buildOverviewValue('Notes', _displayValue(job.notes)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _editActiveJob,
                    icon: const Icon(Icons.edit),
                    label: const Text('Update Active Job'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmEndJob,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End Job'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _page.dispose();
    for (final controller in _autoSaveControllers) {
      controller.removeListener(_scheduleAutoSave);
    }
    for (final controller in _autoSaveControllers) {
      controller.dispose();
    }
    for (final controller in _wellNameControllers) {
      controller.dispose();
    }
    for (final focusNode in _wellNameFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Job Setup', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: _editing
            ? (_startingFreshJob ? 'Start Job' : 'Edit Active Job')
            : (_activeJob == null ? 'Job Setup' : 'Active Job'),
        showBack: true,
      ),
      body: _editing
          ? (_activeWorkflowMode != ActiveWorkflowMode.production
              ? _buildDrilloutCleanoutEditor()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: (_step + 1) / 5),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _autoSaveStatusText(),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _page,
                        physics: const NeverScrollableScrollPhysics(),
                        children: _buildProductionSetupPages(),
                      ),
                    ),
                  ],
                ))
          : (_activeJob == null
              ? _buildNoActiveJobView()
              : _buildActiveJobView(_activeJob!)),
    );
  }

  Widget _buildDrilloutCleanoutEditor() {
    final workflowLabel = _activeWorkflowMode == ActiveWorkflowMode.cleanout
        ? 'Cleanout'
        : 'Drillout';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (_startingFreshJob) ...[
          _startJobWorkflowSelector(),
          const SizedBox(height: 12),
        ],
        Text(
          '$workflowLabel Job Setup',
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            _autoSaveStatusText(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: const Key('job-info-company-field'),
          initialValue:
              _companyOptions().contains(company) ? company.trim() : null,
          decoration: const InputDecoration(labelText: 'Company'),
          items: _companyOptions()
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            _setCompany(value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: padName,
          decoration: const InputDecoration(labelText: 'Location / Pad'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: jobLatitude,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: jobLongitude,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _gpsFilling ? null : _fillCoordinatesFromCurrentLocation,
            icon: _gpsFilling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(_gpsFilling ? 'Capturing GPS...' : 'Use Current GPS'),
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _isMultiWellPad,
          title: const Text('Multi-Well Pad'),
          subtitle: const Text(
            'Enable when this drillout/cleanout job includes multiple wells.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          onChanged: (enabled) {
            final next = enabled ?? false;
            setState(() {
              if (next) {
                jobType = JobProfileDefaultsService.jobTypeMultiWellPad;
                if (wells.isEmpty) {
                  _ensurePerWellCapacity(1);
                }
                if (_drilloutWellName.text.trim().isNotEmpty &&
                    wells[0].trim().isEmpty) {
                  wells[0] = _drilloutWellName.text.trim();
                  leaseNames[0] = _drilloutWellName.text.trim();
                }
              } else {
                jobType = JobProfileDefaultsService.jobTypeSingleWell;
                final firstWell = wells.isNotEmpty ? wells.first.trim() : '';
                if (firstWell.isNotEmpty) {
                  _drilloutWellName.text = firstWell;
                }
                _ensurePerWellCapacity(1);
              }
            });
            _scheduleAutoSave();
          },
        ),
        const SizedBox(height: 10),
        if (!_isMultiWellPad)
          TextField(
            controller: _drilloutWellName,
            decoration: const InputDecoration(labelText: 'Well Name'),
            onChanged: (value) {
              if (wells.isEmpty) {
                _ensurePerWellCapacity(1);
              }
              _setWellNameAt(0, value);
              _setLeaseNameAt(0, value);
              _scheduleAutoSave();
            },
          )
        else ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Wells',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < wells.length; i++) ...[
            Row(
              key: _wellRowKeys[wellIds[i]],
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('job-drillout-well-${wellIds[i]}'),
                    controller: _wellNameControllerAt(i),
                    focusNode: _wellNameFocusNodeAt(i),
                    decoration:
                        InputDecoration(labelText: 'Well ${i + 1} Name'),
                    onChanged: (value) {
                      _setWellNameAt(i, value);
                      _setLeaseNameAt(i, value);
                      if (i == 0 && value.trim().isNotEmpty) {
                        _drilloutWellName.text = value.trim();
                      }
                      _scheduleAutoSave();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed:
                      wells.length > 1 ? () => _removeMultiWellRow(i) : null,
                  tooltip: 'Remove Well',
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addMultiWellRow,
              icon: const Icon(Icons.add),
              label: const Text('Add Well'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: shift,
          decoration: const InputDecoration(labelText: 'Shift'),
          items: const [
            DropdownMenuItem(value: 'Day', child: Text('Day')),
            DropdownMenuItem(value: 'Night', child: Text('Night')),
          ],
          onChanged: (value) {
            setState(() => shift = value ?? 'Day');
            _scheduleAutoSave();
          },
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Workflow'),
          child: Text(workflowLabel),
        ),
        const SizedBox(height: 16),
        const Text(
          'Optional Drillout/Cleanout Defaults',
          style: TextStyle(
            color: Color(0xFFCDA56A),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _drilloutManifoldPsi,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Manifold PSI'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutCasingPsi,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Casing PSI'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutPumpPsi,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Pump PSI'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutRateOverride,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(labelText: 'Rate Override (BBL/min)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutSurfaceTotalFluid,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Surface Total Fluid'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutWaterHauled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Water Hauled'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutOilHauled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Oil Hauled'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutPlugNumber,
          decoration: const InputDecoration(labelText: 'Plug Number'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutStatus,
          decoration: const InputDecoration(labelText: 'Status'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _drilloutCoilDepth,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Coil Depth'),
        ),
        const SizedBox(height: 14),
        const Text(
          'Tank Setup',
          style: TextStyle(
            color: Color(0xFFCDA56A),
            fontWeight: FontWeight.w700,
          ),
        ),
        DropdownButtonFormField<String>(
          key: Key('tank-config-sand-type-${_tankConfig.sandTankType}'),
          initialValue: _tankConfig.sandTankType,
          decoration: const InputDecoration(labelText: 'Sand Tank Type'),
          items: _tankTypeItemsForRole(DrilloutTankCatalog.roleSandTank),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _tankConfig = _tankConfig.copyWith(sandTankType: value);
            });
            _scheduleAutoSave();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          key: Key('tank-config-flowback-count-${_tankConfig.flowbackCount}'),
          initialValue: _tankConfig.flowbackCount,
          decoration:
              const InputDecoration(labelText: 'Flowback Tank Quantity'),
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
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: DropdownButtonFormField<String>(
              key: Key(
                  'tank-config-flowback-type-$i-${_tankConfig.flowbackTankTypes[i]}'),
              initialValue: _tankConfig.flowbackTankTypes[i],
              decoration: InputDecoration(
                labelText: 'Flowback Tank ${i + 1} Type',
              ),
              items: _tankTypeItemsForRole(
                DrilloutTankCatalog.flowbackRoleIds[i],
              ),
              onChanged: (value) {
                if (value == null) return;
                final types = List<String>.from(_tankConfig.flowbackTankTypes);
                types[i] = value;
                setState(() {
                  _tankConfig = _tankConfig.copyWith(flowbackTankTypes: types);
                });
                _scheduleAutoSave();
              },
            ),
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          key: Key('tank-config-sweep-count-${_tankConfig.sweepCount}'),
          initialValue: _tankConfig.sweepCount,
          decoration: const InputDecoration(labelText: 'Sweep Tank Quantity'),
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
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: DropdownButtonFormField<String>(
              key: Key(
                  'tank-config-sweep-type-$i-${_tankConfig.sweepTankTypes[i]}'),
              initialValue: _tankConfig.sweepTankTypes[i],
              decoration: InputDecoration(
                labelText: 'Sweep Tank ${i + 1} Type',
              ),
              items: _tankTypeItemsForRole(
                DrilloutTankCatalog.sweepRoleIds[i],
              ),
              onChanged: (value) {
                if (value == null) return;
                final types = List<String>.from(_tankConfig.sweepTankTypes);
                types[i] = value;
                setState(() {
                  _tankConfig = _tankConfig.copyWith(sweepTankTypes: types);
                });
                _scheduleAutoSave();
              },
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_startingFreshJob ? 'Start Job' : 'Update Active Job'),
        ),
      ],
    );
  }

  Widget _countField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WwNumberField(
        label: label,
        controller: controller,
        allowDecimal: false,
        onChanged: (_) => _scheduleAutoSave(),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}
