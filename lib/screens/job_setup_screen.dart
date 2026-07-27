import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/drillout_tank_configuration.dart';
import '../models/job_setup.dart';
import '../services/active_company_service.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
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
  final _storage = JobStorageService();
  final _profileDefaults = JobProfileDefaultsService();
  final _activeCompanyService = ActiveCompanyService.instance;
  final _workflowModeService = ActiveWorkflowModeService.instance;
  final _page = PageController();
  Timer? _autoSaveTimer;

  int _step = 0;
  bool _loading = true;
  bool _editing = false;
  bool _startingFreshJob = false;
  JobSetup? _activeJob;
  ActiveWorkflowMode _activeWorkflowMode = ActiveWorkflowMode.production;

  String company = 'Mach Energy';
  String jobType = JobProfileDefaultsService.jobTypeSingleWell;
  List<String> wellFieldKeys = const [];
  List<String> activeEquipmentSections = const [];
  final selectedChemicals = <String>[];
  String shift = 'Day';
  final padName = TextEditingController();
  final notes = TextEditingController();
  final leaseName = TextEditingController();
  final county = TextEditingController();
  final state = TextEditingController(text: 'Oklahoma');
  final dateStarted = TextEditingController(
    text: DateFormat('MM/dd/yyyy').format(DateTime.now()),
  );
  final wells = <String>[];
  final wellIds = <String>[];
  final leaseNames = <String>[];
  final wellNameManuallyEdited = <bool>[];

  final sandSeparators = TextEditingController(text: '2');
  final plugCatchers = TextEditingController(text: '1');
  final chokeManifolds = TextEditingController(text: '1');
  final lineHeaters = TextEditingController(text: '1');
  final testUnits = TextEditingController(text: '1');
  final ecds = TextEditingController(text: '1');
  final vrus = TextEditingController(text: '1');
  final flares = TextEditingController(text: '1');
  final transferPumps = TextEditingController(text: '1');

  final oilTanks = TextEditingController(text: '4');
  final oilTankCapacity = TextEditingController(text: '400');
  final waterTanks = TextEditingController(text: '6');
  final waterTankCapacity = TextEditingController(text: '500');
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

  int _i(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 0;
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
    // Build 173: Active Job changes are committed only through explicit
    // Start Job / Update Active Job actions.
  }

  void _applyDrilloutSetupToForm(JobSetup job) {
    final setup = job.drilloutSetup;
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

    if (_drilloutWellName.text.trim().isEmpty && job.primaryWell.isNotEmpty) {
      _drilloutWellName.text = job.primaryWell;
    }
  }

  String _legacyString(dynamic value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  void _resetDrilloutSetupForNewJob() {
    final active = _activeJob;
    _drilloutWellName.text = active?.primaryWell ?? '';
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
  }

  Map<String, dynamic> _buildDrilloutSetupPayload() {
    final payload = <String, dynamic>{
      'wellName': _drilloutWellName.text.trim(),
      'locationPad': padName.text.trim(),
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
      'tankConfigurationV1': _tankConfig.toJson(),
    };

    final roleGauges = <String, String>{
      DrilloutTankCatalog.roleSandTank: _flowbackGauge.text.trim(),
      DrilloutTankCatalog.roleFlowback1: _waterTank1Gauge.text.trim(),
      DrilloutTankCatalog.roleFlowback2: _waterTank2Gauge.text.trim(),
      DrilloutTankCatalog.roleSweep1: _sweepTankGauge.text.trim(),
      ..._tankConfig.gaugesByRole,
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
    if (_drilloutWellName.text.trim().isEmpty) missing.add('Well Name');
    if (shift.trim().isEmpty) missing.add('Shift');
    if (missing.isEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Required: ${missing.join(', ')}')),
    );
    return false;
  }

  JobSetup _buildDrilloutJobFromForm() {
    final well = _drilloutWellName.text.trim();
    final existingId = (_activeJob?.wellEntries.isNotEmpty ?? false)
        ? _activeJob!.wellEntries.first.id
        : JobSetup.generateWellId();
    return JobSetup(
      company: company.trim(),
      workflow: _workflowStorageValue(),
      jobType: JobProfileDefaultsService.jobTypeSingleWell,
      customer: well,
      padName: padName.text.trim(),
      notes: notes.text.trim(),
      leaseName: well,
      leaseNames: <String>[well],
      county: county.text.trim(),
      state: state.text.trim(),
      shift: shift,
      dateStarted: dateStarted.text.trim(),
      status: _activeJob?.status ?? 'active',
      id: _activeJob?.id ?? '',
      startedAt: _activeJob?.startedAt,
      endedAt: _activeJob?.endedAt,
      wells: <String>[well],
      wellEntries: <JobSetupWell>[JobSetupWell(id: existingId, name: well)],
      wellFieldKeys: const <String>[],
      activeEquipmentSections: const <String>[],
      selectedChemicals: const <String>[],
      drilloutSetup: _buildDrilloutSetupPayload(),
    );
  }

  void _applyJobToForm(JobSetup job) {
    company = _profileDefaults.normalizeCompany(job.company);
    jobType = _profileDefaults.normalizeJobType(job.jobType);
    final defaults = _profileDefaults.profileForCompany(company);
    wellFieldKeys = job.wellFieldKeys.isEmpty
        ? List<String>.from(defaults.wellFieldKeys)
        : List<String>.from(job.wellFieldKeys);
    activeEquipmentSections = job.activeEquipmentSections.isEmpty
        ? List<String>.from(defaults.defaultActiveSections)
        : List<String>.from(job.activeEquipmentSections);
    selectedChemicals
      ..clear()
      ..addAll(job.selectedChemicals);
    shift = job.shift;
    padName.text = job.padName;
    notes.text = job.notes;
    leaseName.text = job.leaseName;
    county.text = job.county;
    state.text = job.state;
    dateStarted.text = job.dateStarted.trim().isEmpty
        ? DateFormat('MM/dd/yyyy').format(DateTime.now())
        : job.dateStarted;
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
    selectedChemicals
      ..clear()
      ..addAll(const <String>[]);
    shift = 'Day';
    padName.clear();
    notes.clear();
    leaseName.clear();
    county.clear();
    state.text = 'Oklahoma';
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
    ecds.text = '1';
    vrus.text = '1';
    flares.text = '1';
    transferPumps.text = '1';
    oilTanks.text = '4';
    oilTankCapacity.text = '400';
    waterTanks.text = '6';
    waterTankCapacity.text = '500';
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
      ecds: _i(ecds),
      vrus: _i(vrus),
      flares: _i(flares),
      transferPumps: _i(transferPumps),
      oilTanks: _i(oilTanks),
      oilTankCapacity: oilTankCapacity.text.trim(),
      waterTanks: _i(waterTanks),
      waterTankCapacity: waterTankCapacity.text.trim(),
      productionTankFactor: productionTankFactor.text.trim().isEmpty
          ? '1.67'
          : productionTankFactor.text.trim(),
      selectedChemicals: List<String>.from(selectedChemicals),
      drilloutSetup: _activeJob?.drilloutSetup ?? const <String, dynamic>{},
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

  void _startJobSetup() {
    if (_activeWorkflowMode == ActiveWorkflowMode.production) {
      _resetFormForNewJob();
    } else {
      _resetDrilloutSetupForNewJob();
    }
    setState(() {
      _activeJob = null;
      _startingFreshJob = true;
      _editing = true;
      _step = 0;
    });
    if (_page.hasClients) {
      _page.jumpToPage(0);
    }
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Active job ended')));
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
    final bestIdentifier = job.primaryWell.trim().isNotEmpty
        ? job.primaryWell.trim()
        : (job.padName.trim().isNotEmpty ? job.padName.trim() : '-');
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
                if (isProduction) ...[
                  _buildOverviewValue(
                    'Job Type',
                    _profileDefaults.jobTypeLabel(job.jobType),
                  ),
                  _buildOverviewValue(
                    'Chemicals',
                    job.selectedChemicals.isEmpty
                        ? 'Not selected'
                        : job.selectedChemicals.join(', '),
                  ),
                  _buildOverviewValue(
                    'Active Sections',
                    job.activeEquipmentSections.isEmpty
                        ? defaults.defaultActiveSections.join(', ')
                        : job.activeEquipmentSections.join(', '),
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
    _drilloutWellName.dispose();
    _drilloutManifoldPsi.dispose();
    _drilloutCasingPsi.dispose();
    _drilloutPumpPsi.dispose();
    _drilloutRateOverride.dispose();
    _drilloutSurfaceTotalFluid.dispose();
    _drilloutWaterHauled.dispose();
    _drilloutOilHauled.dispose();
    _drilloutPlugNumber.dispose();
    _drilloutStatus.dispose();
    _drilloutCoilDepth.dispose();
    _flowbackGauge.dispose();
    _waterTank1Gauge.dispose();
    _waterTank2Gauge.dispose();
    _sweepTankGauge.dispose();
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
                      child: LinearProgressIndicator(value: (_step + 1) / 5),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _page,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _StepPage(title: '1. Company', children: [
                            InputDecorator(
                              decoration:
                                  const InputDecoration(labelText: 'Company'),
                              child: Text(
                                  company.trim().isEmpty ? 'None' : company),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: jobType,
                              decoration:
                                  const InputDecoration(labelText: 'Job Type'),
                              items: const [
                                DropdownMenuItem(
                                  value: JobProfileDefaultsService
                                      .jobTypeSingleWell,
                                  child: Text('Single Well'),
                                ),
                                DropdownMenuItem(
                                  value: JobProfileDefaultsService
                                      .jobTypeMultiWellPad,
                                  child: Text('Multi-Well / Pad'),
                                ),
                              ],
                              onChanged: (value) {
                                final nextType =
                                    _profileDefaults.normalizeJobType(value ??
                                        JobProfileDefaultsService
                                            .jobTypeSingleWell);
                                setState(() {
                                  jobType = nextType;
                                  if (jobType ==
                                          JobProfileDefaultsService
                                              .jobTypeSingleWell &&
                                      wells.length != 1) {
                                    _ensurePerWellCapacity(1);
                                  }
                                  if (jobType ==
                                          JobProfileDefaultsService
                                              .jobTypeMultiWellPad &&
                                      wells.isEmpty) {
                                    _ensurePerWellCapacity(2);
                                  }
                                });
                                _scheduleAutoSave();
                              },
                            ),
                            const SizedBox(height: 14),
                            const SizedBox(height: 20),
                            const Text(
                              'Company controls default labels/sections. Job Type controls one well vs multiple wells. Select active chemicals for Quick Round and reports.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 14),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Chemicals',
                                style: TextStyle(
                                  color: Color(0xFFCDA56A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...JobSetup.chemicalOptions.map(
                              (chemical) => CheckboxListTile(
                                value: selectedChemicals.contains(chemical),
                                title: Text(chemical),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (enabled) {
                                  setState(() {
                                    if (enabled ?? false) {
                                      if (!selectedChemicals
                                          .contains(chemical)) {
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
                            const SizedBox(height: 14),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Well Fields',
                                style: TextStyle(
                                  color: Color(0xFFCDA56A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final field in wellFieldKeys)
                                  Chip(
                                    label: Text(field.toUpperCase()),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Active Equipment Sections',
                                style: TextStyle(
                                  color: Color(0xFFCDA56A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._profileDefaults
                                .profileForCompany(company)
                                .optionalSections
                                .map(
                                  (section) => CheckboxListTile(
                                    value: activeEquipmentSections
                                        .contains(section),
                                    title: Text(section),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (enabled) {
                                      setState(() {
                                        if (enabled ?? false) {
                                          if (!activeEquipmentSections
                                              .contains(section)) {
                                            activeEquipmentSections
                                                .add(section);
                                          }
                                        } else {
                                          activeEquipmentSections
                                              .remove(section);
                                        }
                                      });
                                      _scheduleAutoSave();
                                    },
                                  ),
                                ),
                            const SizedBox(height: 24),
                            _navButtons(),
                          ]),
                          _StepPage(title: '2. Job Info', children: [
                            TextField(
                              controller: padName,
                              decoration:
                                  const InputDecoration(labelText: 'Pad Name'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: notes,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Notes (Optional)',
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (jobType ==
                                JobProfileDefaultsService.jobTypeSingleWell)
                              TextField(
                                controller: leaseName,
                                decoration: const InputDecoration(
                                  labelText: 'Lease Name',
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _ensurePerWellCapacity(1);
                                    _setLeaseNameAt(0, value);
                                  });
                                  _scheduleAutoSave();
                                },
                              )
                            else ...[
                              const Text(
                                'Per-Well Lease Names',
                                style: TextStyle(
                                  color: Color(0xFFCDA56A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Number of Wells',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: TextFormField(
                                      key: ValueKey(
                                          'well-count-${wells.length}'),
                                      initialValue:
                                          '${wells.length < 2 ? 2 : wells.length}',
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Count',
                                      ),
                                      onChanged: (value) {
                                        final parsed =
                                            int.tryParse(value.trim()) ?? 2;
                                        final next = parsed < 2 ? 2 : parsed;
                                        setState(() {
                                          _ensurePerWellCapacity(next);
                                        });
                                        _scheduleAutoSave();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              for (int i = 0; i < wells.length; i++) ...[
                                Text(
                                  'Well ${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  key: ValueKey(
                                      'lease-$i-${i < leaseNames.length ? leaseNames[i] : ''}'),
                                  initialValue: i < leaseNames.length
                                      ? leaseNames[i]
                                      : '',
                                  decoration: const InputDecoration(
                                    labelText: 'Lease Name',
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _setLeaseNameAt(i, value);
                                    });
                                    _scheduleAutoSave();
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              controller: county,
                              decoration:
                                  const InputDecoration(labelText: 'County'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: state,
                              decoration:
                                  const InputDecoration(labelText: 'State'),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: shift,
                              decoration:
                                  const InputDecoration(labelText: 'Shift'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Day',
                                  child: Text('Day'),
                                ),
                                DropdownMenuItem(
                                  value: 'Night',
                                  child: Text('Night'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() => shift = value ?? 'Day');
                                _scheduleAutoSave();
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: dateStarted,
                              decoration:
                                  const InputDecoration(labelText: 'Date'),
                            ),
                            const SizedBox(height: 24),
                            _navButtons(),
                          ]),
                          _StepPage(title: '3. Wells', children: [
                            if (jobType ==
                                JobProfileDefaultsService.jobTypeSingleWell)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Single Well selected. Add one well name.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Multi-Well / Pad selected. Add all well names for this pad.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            for (int i = 0; i < wells.length; i++) ...[
                              TextFormField(
                                key: ValueKey('well-$i-${wells[i]}'),
                                initialValue: wells[i],
                                decoration: InputDecoration(
                                  labelText: 'Well ${i + 1} Name',
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _setWellNameAt(i, value);
                                  });
                                  _scheduleAutoSave();
                                },
                              ),
                              const SizedBox(height: 10),
                              if (i < leaseNames.length &&
                                  leaseNames[i].trim().isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Lease Name: ${leaseNames[i].trim()}',
                                    style:
                                        const TextStyle(color: Colors.white70),
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 24),
                            _navButtons(),
                          ]),
                          _StepPage(title: '4. Equipment', children: [
                            _countField('Sand Separators', sandSeparators),
                            _countField('Plug Catchers', plugCatchers),
                            _countField('Choke Manifolds', chokeManifolds),
                            _countField('Line Heaters', lineHeaters),
                            _countField('Test Units', testUnits),
                            _countField('ECDs', ecds),
                            _countField('VRUs', vrus),
                            _countField('Flares', flares),
                            _countField('Transfer Pumps', transferPumps),
                            const SizedBox(height: 24),
                            _navButtons(),
                          ]),
                          _StepPage(title: '5. Tanks', children: [
                            _countField('Oil Tanks', oilTanks),
                            WwNumberField(
                              label: 'Oil Tank Capacity',
                              controller: oilTankCapacity,
                            ),
                            _countField('Water Tanks', waterTanks),
                            WwNumberField(
                              label: 'Water Tank Capacity',
                              controller: waterTankCapacity,
                            ),
                            WwNumberField(
                              label: 'Production Tank Factor (BBL/In)',
                              controller: productionTankFactor,
                              allowDecimal: true,
                            ),
                            const Text(
                              'Default tank factor stays 1.67 unless you change it.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 18),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  'Summary\n$company\n${_profileDefaults.jobTypeLabel(jobType)}\n${padName.text.trim().isEmpty ? 'No pad entered' : padName.text.trim()}\n${wells.length} well(s)\nChemicals: ${selectedChemicals.isEmpty ? 'None' : selectedChemicals.join(', ')}\nSections: ${activeEquipmentSections.isEmpty ? 'None' : activeEquipmentSections.join(', ')}\n${_i(sandSeparators) + _i(plugCatchers) + _i(chokeManifolds) + _i(lineHeaters) + _i(testUnits) + _i(ecds) + _i(vrus) + _i(flares) + _i(transferPumps)} equipment item(s)\n${_i(oilTanks) + _i(waterTanks)} tank(s)',
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _navButtons(finish: true),
                          ]),
                        ],
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
        Text(
          '$workflowLabel Job Setup',
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Company'),
          child: Text(company.trim().isEmpty ? '-' : company),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: padName,
          decoration: const InputDecoration(labelText: 'Location / Pad'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _drilloutWellName,
          decoration: const InputDecoration(labelText: 'Well Name'),
        ),
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
          key: const Key('tank-config-sand-type'),
          initialValue: _tankConfig.sandTankType,
          decoration: const InputDecoration(labelText: 'Sand Tank Type'),
          items: _tankTypeItemsForRole(DrilloutTankCatalog.roleSandTank),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _tankConfig = _tankConfig.copyWith(sandTankType: value);
            });
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          key: const Key('tank-config-flowback-count'),
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
              key: Key('tank-config-flowback-type-$i'),
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
              },
            ),
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          key: const Key('tank-config-sweep-count'),
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
              key: Key('tank-config-sweep-type-$i'),
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
