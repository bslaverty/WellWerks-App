import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/active_company_service.dart';
import '../services/app_settings_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/report_profile_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class ProductionInventoryScreen extends StatefulWidget {
  const ProductionInventoryScreen({
    super.key,
    this.embedded = false,
    this.showManageLayoutsButton = true,
  });

  final bool embedded;
  final bool showManageLayoutsButton;

  @override
  State<ProductionInventoryScreen> createState() =>
      _ProductionInventoryScreenState();
}

class _ProductionInventoryScreenState extends State<ProductionInventoryScreen> {
  final _service = ProductionShiftService();
  final _settingsService = AppSettingsService();
  final _layoutService = ReportProfileService();
  final _jobStorage = JobStorageService();
  final _activeCompanyService = ActiveCompanyService.instance;

  final _company = TextEditingController();
  final _pad = TextEditingController();
  final _date = TextEditingController();
  String _gaugeEntryType = 'inches';
  String _gasUnit = 'mcfd';
  String _gasCalculationMethod = 'accumulator';
  String _layoutProfileId = 'default';
  bool _useJobSetupTanks = true;
  final _startingGasAccum = TextEditingController();
  final _waterHauledBeforeRound = TextEditingController();
  final _oilHauledBeforeRound = TextEditingController();
  final _waterPumpedBeforeRound = TextEditingController();
  final _oilPumpedBeforeRound = TextEditingController();

  final List<TextEditingController> _wellControllers = [];
  final List<String> _wellIdentityIds = [];
  final List<String> _wellChokeTypes = [];
  final List<_TankControllers> _waterTanks = [];
  final List<_TankControllers> _oilTanks = [];
  final List<_OilInventoryControllers> _oilInventoryWells = [];
  List<ReportLayoutProfile> _layoutProfiles = const [];
  String _defaultBblPerInch = '1.67';
  String _defaultChokeDisplay = 'ADJ';

  bool _loading = true;
  bool _saving = false;
  ProductionShift _activeShift = ProductionShift.empty();
  JobSetup? _activeJobSetup;
  int _selectedWellIndex = 0;
  final Set<TextEditingController> _missingControllers =
      <TextEditingController>{};
  final Set<TextEditingController> _invalidControllers =
      <TextEditingController>{};
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _activeCompanyService.activeCompany
        .addListener(_handleActiveCompanyChanged);
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _load();
  }

  Future<void> _handleActiveCompanyChanged() async {
    if (!mounted) return;
    await _load();
  }

  Future<void> _handleActiveJobChanged() async {
    if (!mounted) return;
    await _load();
  }

  @override
  void dispose() {
    _activeCompanyService.activeCompany
        .removeListener(_handleActiveCompanyChanged);
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    for (final controller in [
      _company,
      _pad,
      _date,
      _startingGasAccum,
      _waterHauledBeforeRound,
      _oilHauledBeforeRound,
      _waterPumpedBeforeRound,
      _oilPumpedBeforeRound,
    ]) {
      controller.dispose();
    }
    for (final controller in _wellControllers) {
      controller.dispose();
    }
    for (final tank in _waterTanks) {
      tank.dispose();
    }
    for (final tank in _oilTanks) {
      tank.dispose();
    }
    for (final well in _oilInventoryWells) {
      well.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final shift = await _service.loadActiveShift();
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    _activeJobSetup = activeJob;
    final settings = await _settingsService.load();
    _layoutProfiles = await _layoutService.loadProfiles();
    final activeLayoutId = await _layoutService.loadActiveProfileId();
    _setFromShift(shift);
    _activeShift = shift;
    _useJobSetupTanks = shift.inventory.useJobSetupTanks;
    if (_useJobSetupTanks && activeJob != null) {
      _applyJobSetupDefaults(activeJob);
    }
    _defaultBblPerInch = settings.defaultBblPerInch;
    _defaultChokeDisplay = settings.defaultChokeDisplay;
    final activeCompany = await _activeCompanyService.ensureLoaded();
    _company.text = activeCompany == JobProfileDefaultsService.companyNone
        ? ''
        : activeCompany;
    if (_isEffectivelyEmptyShift(shift)) {
      _gaugeEntryType = settings.defaultGaugeType;
      _gasUnit = settings.defaultGasUnit;
      _gasCalculationMethod = settings.defaultGasCalculationMethod;
      for (var i = 0; i < _wellChokeTypes.length; i++) {
        _wellChokeTypes[i] = settings.defaultChokeDisplay;
      }
      for (final tank in [..._waterTanks, ..._oilTanks]) {
        tank.bblPerInch.text = settings.defaultBblPerInch;
      }
    }
    final requested = shift.header.layoutProfileId;
    _layoutProfileId = _layoutProfiles.any((p) => p.id == requested)
        ? requested
        : (_layoutProfiles.any((p) => p.id == activeLayoutId)
            ? activeLayoutId
            : _layoutProfiles.first.id);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  bool _isEffectivelyEmptyShift(ProductionShift shift) {
    return shift.header.company.trim().isEmpty &&
        shift.header.pad.trim().isEmpty &&
        shift.header.date.trim().isEmpty &&
        shift.savedRows.isEmpty &&
        shift.hourlyChecks.isEmpty &&
        shift.inventory.startingGasAccum.trim().isEmpty &&
        shift.inventory.oilInventoryWells.every((well) =>
            well.wellName.trim().isEmpty &&
            well.beginningOilInventory.trim().isEmpty &&
            well.currentOilInventory.trim().isEmpty &&
            well.expectedOilInventory.trim().isEmpty &&
            well.currentCushion.trim().isEmpty &&
            well.maximumCushion.trim().isEmpty);
  }

  List<String> get _activeJobWells =>
      (_activeJobSetup?.resolvedWellNames ?? const <String>[])
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

  List<String> get _activeJobWellIds {
    final activeJob = _activeJobSetup;
    if (activeJob == null) return const <String>[];
    final ids = activeJob.wellIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (ids.length == _activeJobWells.length) {
      return ids;
    }
    return [
      for (int i = 0; i < _activeJobWells.length; i++)
        JobSetup.generateWellId(),
    ];
  }

  int get _resolvedSelectedWellIndex {
    if (_wellControllers.isEmpty) return -1;
    if (_selectedWellIndex < 0 ||
        _selectedWellIndex >= _wellControllers.length) {
      return 0;
    }
    return _selectedWellIndex;
  }

  String _normalizeWellName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  void _setFromShift(ProductionShift shift) {
    final fromJobWells = _activeJobWells;
    final fromJobWellIds = _activeJobWellIds;
    _company.text = _activeJobSetup?.company.trim().isNotEmpty == true
        ? _activeJobSetup!.company.trim()
        : shift.header.company;
    _pad.text = _activeJobSetup?.padName.trim().isNotEmpty == true
        ? _activeJobSetup!.padName.trim()
        : shift.header.pad;
    _date.text =
        shift.header.date.trim().isEmpty ? _todayDateText() : shift.header.date;
    _gaugeEntryType = shift.inventory.gaugeEntryType;
    _gasUnit = shift.inventory.gasUnit;
    _gasCalculationMethod = shift.inventory.gasCalculationMethod;
    final requestedLayout = shift.header.layoutProfileId;
    if (_layoutProfiles.isNotEmpty) {
      _layoutProfileId = _layoutProfiles.any((p) => p.id == requestedLayout)
          ? requestedLayout
          : _layoutProfiles.first.id;
    }
    _startingGasAccum.text = shift.inventory.startingGasAccum;
    _useJobSetupTanks = shift.inventory.useJobSetupTanks;
    _waterHauledBeforeRound.text = shift.inventory.waterHauledBeforeRound;
    _oilHauledBeforeRound.text = shift.inventory.oilHauledBeforeRound;
    _waterPumpedBeforeRound.text = shift.inventory.waterPumpedBeforeRound;
    _oilPumpedBeforeRound.text = shift.inventory.oilPumpedBeforeRound;

    for (final controller in _wellControllers) {
      controller.dispose();
    }
    final sourceWells =
        fromJobWells.isNotEmpty ? fromJobWells : shift.header.wells;
    final sourceWellIds = fromJobWells.isNotEmpty
        ? fromJobWellIds
        : (shift.header.wellIds.length == sourceWells.length
            ? shift.header.wellIds
            : [
                for (int i = 0; i < sourceWells.length; i++)
                  JobSetup.legacyWellId(sourceWells[i], i),
              ]);
    _wellControllers
      ..clear()
      ..addAll(sourceWells.map((well) => TextEditingController(text: well)));
    _wellIdentityIds
      ..clear()
      ..addAll(sourceWellIds);
    _wellChokeTypes
      ..clear()
      ..addAll(sourceWells.map((well) =>
          shift.header.wellChokeTypes[well] ?? shift.header.chokeType));
    _defaultChokeDisplay = shift.header.chokeType;

    for (final tank in _waterTanks) {
      tank.dispose();
    }
    _waterTanks
      ..clear()
      ..addAll(shift.inventory.waterTanks.map(_TankControllers.fromTank));

    for (final tank in _oilTanks) {
      tank.dispose();
    }
    _oilTanks
      ..clear()
      ..addAll(shift.inventory.oilTanks.map(_TankControllers.fromTank));

    for (final well in _oilInventoryWells) {
      well.dispose();
    }
    _oilInventoryWells
      ..clear()
      ..addAll(
          _buildOilInventoryControllers(shift.inventory.oilInventoryWells));
  }

  List<_OilInventoryControllers> _buildOilInventoryControllers(
    List<ProductionOilInventoryWell> existing,
  ) {
    return [
      for (int i = 0; i < _wellControllers.length; i++)
        _OilInventoryControllers.fromWell(
          existing: i < existing.length ? existing[i] : null,
        ),
    ];
  }

  List<ProductionReportRow> get _productionRows {
    if (_activeShift.inventory.productionRows.isNotEmpty) {
      return _activeShift.inventory.productionRows;
    }
    return _activeShift.savedRows;
  }

  void _setTankCount(
    List<_TankControllers> tanks,
    int desiredCount,
    String label,
    String defaultBblPerInch,
  ) {
    final normalized = desiredCount < 1 ? 1 : desiredCount;
    while (tanks.length < normalized) {
      tanks.add(_TankControllers(
        name: TextEditingController(text: '$label ${tanks.length + 1}'),
        gaugeInches: TextEditingController(),
        gaugeFeet: TextEditingController(),
        gaugeInchesPart: TextEditingController(),
        gaugeDecimalFeet: TextEditingController(),
        bblPerInch: TextEditingController(text: defaultBblPerInch),
      ));
    }
    while (tanks.length > normalized) {
      final removed = tanks.removeLast();
      removed.dispose();
    }
    for (int i = 0; i < tanks.length; i++) {
      if (tanks[i].name.text.trim().isEmpty) {
        tanks[i].name.text = '$label ${i + 1}';
      }
      if (tanks[i].bblPerInch.text.trim().isEmpty) {
        tanks[i].bblPerInch.text = defaultBblPerInch;
      }
    }
  }

  void _setWellCountFromJob(JobSetup activeJob) {
    final targetWells = activeJob.resolvedWellNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final targetIds = activeJob.wellIds;
    final existingNames = _wellControllers
        .map((controller) => controller.text.trim())
        .toList(growable: false);
    final existingIds = List<String>.from(_wellIdentityIds);
    final existingChokeTypes = List<String>.from(_wellChokeTypes);
    final existingOilInventory = List<_OilInventoryControllers>.from(
      _oilInventoryWells,
    );
    final usedExistingIndexes = <int>{};

    int? resolveExistingIndex(String targetId, String targetName) {
      if (targetId.trim().isNotEmpty) {
        final byId = <int>[];
        for (int i = 0;
            i < existingIds.length && i < existingNames.length;
            i++) {
          if (existingIds[i] == targetId && !usedExistingIndexes.contains(i)) {
            byId.add(i);
          }
        }
        if (byId.length == 1) {
          return byId.first;
        }
      }

      final normalizedTarget = _normalizeWellName(targetName);
      final byName = <int>[];
      for (int i = 0; i < existingNames.length; i++) {
        if (_normalizeWellName(existingNames[i]) == normalizedTarget &&
            !usedExistingIndexes.contains(i)) {
          byName.add(i);
        }
      }
      if (byName.length == 1) {
        return byName.first;
      }

      if (targetWells.length == 1 && existingNames.length == 1) {
        return 0;
      }
      return null;
    }

    final nextWellControllers = <TextEditingController>[];
    final nextWellIds = <String>[];
    final nextChokeTypes = <String>[];
    final nextOilInventory = <_OilInventoryControllers>[];

    for (int i = 0; i < targetWells.length; i++) {
      final targetWell = targetWells[i];
      final targetId = i < targetIds.length && targetIds[i].trim().isNotEmpty
          ? targetIds[i].trim()
          : JobSetup.generateWellId();
      final existingIndex = resolveExistingIndex(targetId, targetWell);
      if (existingIndex != null) {
        usedExistingIndexes.add(existingIndex);
      }

      nextWellControllers.add(TextEditingController(text: targetWell));
      nextWellIds.add(targetId);
      nextChokeTypes.add(existingIndex == null
          ? _defaultChokeDisplay
          : existingChokeTypes[existingIndex]);
      nextOilInventory.add(existingIndex == null
          ? _OilInventoryControllers.blank()
          : _OilInventoryControllers.copyOf(
              existingOilInventory[existingIndex]));
    }

    for (final controller in _wellControllers) {
      controller.dispose();
    }
    for (final well in _oilInventoryWells) {
      well.dispose();
    }

    _wellControllers
      ..clear()
      ..addAll(nextWellControllers);
    _wellIdentityIds
      ..clear()
      ..addAll(nextWellIds);
    _wellChokeTypes
      ..clear()
      ..addAll(nextChokeTypes);
    _oilInventoryWells
      ..clear()
      ..addAll(nextOilInventory);

    if (_wellControllers.isNotEmpty) {
      _selectedWellIndex = _resolvedSelectedWellIndex;
    } else {
      _selectedWellIndex = 0;
    }
  }

  void _applyJobSetupDefaults(JobSetup activeJob) {
    _setWellCountFromJob(activeJob);
    _pad.text = activeJob.padName.trim();
    final defaultFactor = activeJob.productionTankFactor.trim().isEmpty
        ? _defaultBblPerInch
        : activeJob.productionTankFactor.trim();
    _setTankCount(
      _waterTanks,
      activeJob.waterTanks,
      'Water Tank',
      defaultFactor,
    );
    _setTankCount(
      _oilTanks,
      activeJob.oilTanks,
      'Oil Tank',
      defaultFactor,
    );
  }

  double _sumRow(double Function(ProductionReportRow row) accessor) {
    var total = 0.0;
    for (final row in _productionRows) {
      total += accessor(row);
    }
    return total;
  }

  String _fmt(double value) {
    if (value.isNaN) return '--';
    final rounded = value.abs() < 0.01 ? 0 : value;
    return rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  ProductionReportRow? get _latestProductionRow {
    if (_productionRows.isEmpty) return null;
    final sorted = List<ProductionReportRow>.from(_productionRows)
      ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
    return sorted.last;
  }

  void _syncComputedCushion(int index) {
    if (index < 0 || index >= _oilInventoryWells.length) return;
    _oilInventoryWells[index].setComputedCushion();
  }

  ProductionShiftHeader _headerFromControllers() {
    final wells = <String>[];
    final wellIds = <String>[];
    for (int i = 0; i < _wellControllers.length; i++) {
      final name = _wellControllers[i].text.trim();
      if (name.isEmpty) continue;
      wells.add(name);
      final id =
          i < _wellIdentityIds.length && _wellIdentityIds[i].trim().isNotEmpty
              ? _wellIdentityIds[i].trim()
              : JobSetup.generateWellId();
      wellIds.add(id);
    }
    final sourceCompany = _activeJobSetup?.company.trim().isNotEmpty == true
        ? _activeJobSetup!.company.trim()
        : _company.text.trim();
    final sourcePad = _activeJobSetup?.padName.trim().isNotEmpty == true
        ? _activeJobSetup!.padName.trim()
        : _pad.text.trim();
    return ProductionShiftHeader(
      company: sourceCompany,
      pad: sourcePad,
      date: _date.text.trim(),
      layoutProfileId: _layoutProfileId,
      chokeType: _defaultChokeDisplay,
      wellIds: wellIds,
      wellChokeTypes: {
        for (int i = 0; i < _wellControllers.length; i++)
          if (_wellControllers[i].text.trim().isNotEmpty)
            _wellControllers[i].text.trim(): _wellChokeTypes[i]
      },
      wells: wells,
    );
  }

  Future<void> _manageLayouts() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Manage layouts in Text/Report Layouts.'),
      ),
    );
  }

  String _todayDateText() {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day);
    return local.toIso8601String().split('T').first;
  }

  ProductionInventoryBaseline _inventoryFromControllers() {
    final namedWells = _wellControllers
        .map((controller) => controller.text.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return ProductionInventoryBaseline(
      waterTanks:
          _waterTanks.map((tank) => tank.toTank(_gaugeEntryType)).toList(),
      oilTanks: _oilTanks.map((tank) => tank.toTank(_gaugeEntryType)).toList(),
      oilInventoryWells: [
        for (int i = 0;
            i < namedWells.length && i < _oilInventoryWells.length;
            i++)
          _oilInventoryWells[i].toWell(
            namedWells[i],
          ),
      ],
      gaugeEntryType: _gaugeEntryType,
      useJobSetupTanks: _useJobSetupTanks,
      productionRows: _productionRows,
      gasUnit: _gasUnit,
      gasCalculationMethod: _gasCalculationMethod,
      startingGasAccum: _startingGasAccum.text.trim(),
      waterHauledBeforeRound: _waterHauledBeforeRound.text.trim(),
      oilHauledBeforeRound: _oilHauledBeforeRound.text.trim(),
      waterPumpedBeforeRound: _waterPumpedBeforeRound.text.trim(),
      oilPumpedBeforeRound: _oilPumpedBeforeRound.text.trim(),
    );
  }

  Future<void> _saveInventory() async {
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    _activeJobSetup = activeJob;
    if (activeJob == null || activeJob.resolvedWellNames.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No active wells. Start or edit a job to add well names.',
          ),
        ),
      );
      return;
    }
    if (_useJobSetupTanks) {
      setState(() {
        _applyJobSetupDefaults(activeJob);
      });
    } else {
      setState(() {
        _setWellCountFromJob(activeJob);
        _pad.text = activeJob.padName.trim();
      });
    }

    final missing = <TextEditingController>{};
    final invalid = <TextEditingController>{};

    void requireFilled(TextEditingController controller) {
      if (controller.text.trim().isEmpty) {
        missing.add(controller);
      }
    }

    void disallowNegative(TextEditingController controller) {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      final value = double.tryParse(text);
      if (value != null && value < 0) {
        invalid.add(controller);
      }
    }

    requireFilled(_company);
    requireFilled(_date);

    for (final controller in [
      _startingGasAccum,
      _waterHauledBeforeRound,
      _oilHauledBeforeRound,
      _waterPumpedBeforeRound,
      _oilPumpedBeforeRound,
    ]) {
      disallowNegative(controller);
    }

    for (final tank in [..._waterTanks, ..._oilTanks]) {
      for (final controller in [
        tank.gaugeInches,
        tank.gaugeFeet,
        tank.gaugeInchesPart,
        tank.gaugeDecimalFeet,
        tank.bblPerInch,
      ]) {
        disallowNegative(controller);
      }
    }

    for (final well in _oilInventoryWells) {
      for (final controller in [
        well.beginningOilInventory,
        well.currentOilInventory,
        well.expectedOilInventory,
        well.maximumCushion,
      ]) {
        disallowNegative(controller);
      }
    }

    setState(() {
      _missingControllers
        ..clear()
        ..addAll(missing);
      _invalidControllers
        ..clear()
        ..addAll(invalid);
      if (missing.isNotEmpty) {
        _validationMessage =
            'Fill the highlighted required Production Setup fields before saving.';
      } else if (invalid.isNotEmpty) {
        _validationMessage =
            'Negative values are not valid in the highlighted Production Inventory fields.';
      } else {
        _validationMessage = null;
      }
    });

    if (missing.isNotEmpty || invalid.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_validationMessage!)),
      );
      return;
    }

    final active = await _service.loadActiveShift();
    final updated = active.copyWith(
      header: _headerFromControllers(),
      inventory: _inventoryFromControllers(),
    );

    final warnings = <String>[];
    for (var i = 0;
        i < _waterTanks.length && i < active.inventory.waterTanks.length;
        i++) {
      final previous = active.inventory.waterTanks[i].gaugeEntry.asInches();
      final current = _waterTanks[i].gaugeEntry(_gaugeEntryType).asInches();
      if ((current - previous).abs() > 24) {
        warnings
            .add('Water Tank ${i + 1} gauge changed by more than 24 inches.');
      }
    }
    for (var i = 0;
        i < _oilTanks.length && i < active.inventory.oilTanks.length;
        i++) {
      final previous = active.inventory.oilTanks[i].gaugeEntry.asInches();
      final current = _oilTanks[i].gaugeEntry(_gaugeEntryType).asInches();
      if ((current - previous).abs() > 24) {
        warnings.add('Oil Tank ${i + 1} gauge changed by more than 24 inches.');
      }
    }
    final previousGas =
        double.tryParse(active.inventory.startingGasAccum.trim());
    final currentGas = double.tryParse(_startingGasAccum.text.trim());
    if (previousGas != null &&
        currentGas != null &&
        (currentGas - previousGas).abs() > 1000) {
      warnings.add('Starting gas accumulator changed by more than 1000.');
    }

    if (warnings.isNotEmpty) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirm Save'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These values are outside the normal operating range. Save anyway?',
                  ),
                  const SizedBox(height: 10),
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $warning'),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save Anyway'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    setState(() => _saving = true);
    await _service.saveActiveShift(updated);
    if (!mounted) return;
    setState(() {
      _activeShift = updated;
      _saving = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Production Inventory saved successfully.')),
    );
  }

  void _clearFieldIssue(TextEditingController controller) {
    if (!_missingControllers.contains(controller) &&
        !_invalidControllers.contains(controller)) {
      return;
    }
    setState(() {
      _missingControllers.remove(controller);
      _invalidControllers.remove(controller);
      if (_missingControllers.isEmpty && _invalidControllers.isEmpty) {
        _validationMessage = null;
      }
    });
  }

  String? _errorTextFor(TextEditingController controller) {
    if (_missingControllers.contains(controller)) {
      return 'Required';
    }
    if (_invalidControllers.contains(controller)) {
      return 'Cannot be negative';
    }
    return null;
  }

  Widget _validationCard() {
    final message = _validationMessage;
    if (message == null) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFF3A1E1E),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _clearInventory() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Inventory?'),
            content: const Text(
              'This clears the shift header, starting inventory, starting gas, and pre-round adjustments.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Inventory'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final active = await _service.loadActiveShift();
    final cleared = active.copyWith(
      header: const ProductionShiftHeader(),
      inventory: ProductionInventoryBaseline.empty(),
    );
    await _service.saveActiveShift(cleared);
    _setFromShift(cleared);
    _activeShift = cleared;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Production Inventory cleared.')),
    );
  }

  void _addTank(List<_TankControllers> list, String label) {
    if (_useJobSetupTanks && _activeJobSetup != null) return;
    setState(() {
      list.add(_TankControllers(
        name: TextEditingController(text: '$label ${list.length + 1}'),
        gaugeInches: TextEditingController(),
        gaugeFeet: TextEditingController(),
        gaugeInchesPart: TextEditingController(),
        gaugeDecimalFeet: TextEditingController(),
        bblPerInch: TextEditingController(text: _defaultBblPerInch),
      ));
    });
  }

  void _removeTank(List<_TankControllers> list, int index) {
    if (_useJobSetupTanks && _activeJobSetup != null) return;
    if (list.length == 1) return;
    setState(() {
      final tank = list.removeAt(index);
      tank.dispose();
    });
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          errorText: _errorTextFor(controller),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
        onChanged: (_) {
          _clearFieldIssue(controller);
          setState(() {});
        },
      ),
    );
  }

  List<Widget> _gaugeInputFields(_TankControllers tank) {
    if (_gaugeEntryType == 'feetInches') {
      return [
        WwNumberField(
          label: 'Gauge Feet',
          controller: tank.gaugeFeet,
          errorText: _errorTextFor(tank.gaugeFeet),
          onChanged: (_) {
            _clearFieldIssue(tank.gaugeFeet);
            setState(() {});
          },
        ),
        WwNumberField(
          label: 'Gauge Inches',
          controller: tank.gaugeInchesPart,
          errorText: _errorTextFor(tank.gaugeInchesPart),
          onChanged: (_) {
            _clearFieldIssue(tank.gaugeInchesPart);
            setState(() {});
          },
        ),
      ];
    }
    if (_gaugeEntryType == 'decimalFeet') {
      return [
        WwNumberField(
          label: 'Gauge (decimal feet)',
          controller: tank.gaugeDecimalFeet,
          errorText: _errorTextFor(tank.gaugeDecimalFeet),
          onChanged: (_) {
            _clearFieldIssue(tank.gaugeDecimalFeet);
            setState(() {});
          },
        ),
      ];
    }
    return [
      WwNumberField(
        label: 'Gauge (inches)',
        controller: tank.gaugeInches,
        errorText: _errorTextFor(tank.gaugeInches),
        onChanged: (_) {
          _clearFieldIssue(tank.gaugeInches);
          setState(() {});
        },
      ),
    ];
  }

  Widget _tankSection({
    required String title,
    required List<_TankControllers> tanks,
    required String tankLabel,
  }) {
    return _section(title, [
      for (int i = 0; i < tanks.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$tankLabel ${i + 1}',
                        style: const TextStyle(
                          color: Color(0xFFCDA56A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          (_useJobSetupTanks && _activeJobSetup != null) ||
                                  tanks.length == 1
                              ? null
                              : () => _removeTank(tanks, i),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                _textField(
                  'Tank Name',
                  tanks[i].name,
                  enabled: !(_useJobSetupTanks && _activeJobSetup != null),
                ),
                ..._gaugeInputFields(tanks[i]),
                WwNumberField(
                  label: 'BBL per inch',
                  controller: tanks[i].bblPerInch,
                  helperText: 'Default 1.67',
                  errorText: _errorTextFor(tanks[i].bblPerInch),
                  onChanged: (_) {
                    _clearFieldIssue(tanks[i].bblPerInch);
                    setState(() {});
                  },
                ),
                Text(
                  'Entered: ${tanks[i].gaugeEntryText(_gaugeEntryType)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  'Converted Gauge: ${tanks[i].convertedGaugeText(_gaugeEntryType)} in',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  'Starting BBL: ${tanks[i].calculatedBbl(_gaugeEntryType).toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFCDA56A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: (_useJobSetupTanks && _activeJobSetup != null)
              ? null
              : () => _addTank(tanks, tankLabel),
          icon: const Icon(Icons.add),
          label: Text('Add $tankLabel'),
        ),
      ),
    ]);
  }

  Widget _runningTotalsSection() {
    final latest = _latestProductionRow;
    final totalOilHauled = _sumRow((row) => row.oilHauled) +
        (double.tryParse(_oilHauledBeforeRound.text.trim()) ?? 0);
    final totalWaterHauled = _sumRow((row) => row.waterHauled) +
        (double.tryParse(_waterHauledBeforeRound.text.trim()) ?? 0);
    final totalWaterPumped = _sumRow((row) => row.waterPumped) +
        (double.tryParse(_waterPumpedBeforeRound.text.trim()) ?? 0);
    final avgOilRateRows =
        _productionRows.where((row) => row.oilProduction >= 0).toList();
    final avgWaterRateRows =
        _productionRows.where((row) => row.waterProduction >= 0).toList();
    final avgOilRate = avgOilRateRows.isEmpty
        ? double.nan
        : avgOilRateRows
                .map((row) => row.oilProduction)
                .reduce((a, b) => a + b) /
            avgOilRateRows.length;
    final avgWaterRate = avgWaterRateRows.isEmpty
        ? double.nan
        : avgWaterRateRows
                .map((row) => row.waterProduction)
                .reduce((a, b) => a + b) /
            avgWaterRateRows.length;
    final recentRows = List<ProductionReportRow>.from(_productionRows)
      ..sort((a, b) => b.hourIndex.compareTo(a.hourIndex));

    return _section('Running Production Totals', [
      Text(
        'Entries saved from Quick Round: ${_productionRows.length}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      Text('Oil hauled total: ${_fmt(totalOilHauled)} BBL'),
      Text('Water hauled total: ${_fmt(totalWaterHauled)} BBL'),
      Text('Water pumped total: ${_fmt(totalWaterPumped)} BBL'),
      const SizedBox(height: 8),
      Text(
          'Oil currently on location: ${_fmt(latest?.currentOilBbl ?? double.nan)} BBL'),
      Text(
          'Water currently on location: ${_fmt(latest?.currentWaterBbl ?? double.nan)} BBL'),
      Text('Oil production rate: ${_fmt(avgOilRate)} BBL/hr'),
      Text('Water production rate: ${_fmt(avgWaterRate)} BBL/hr'),
      const SizedBox(height: 12),
      const Text(
        'Recent Historical Readings',
        style: TextStyle(
          color: Color(0xFFCDA56A),
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      if (recentRows.isEmpty)
        const Text(
          'No readings saved yet. Save a Quick Round entry to begin history.',
          style: TextStyle(color: Colors.white70),
        )
      else
        for (final row in recentRows.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${row.time} • ${row.well} • Oil ${_fmt(row.oilProduction)} / Water ${_fmt(row.waterProduction)} BBL/hr',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
    ]);
  }

  Widget _oilInventorySection() {
    final selectedWellIndex = _resolvedSelectedWellIndex;
    return _section('Oil Inventory Foundation', [
      const Text(
        'Track starting oil inventory for the selected well on the active shift.',
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      if (selectedWellIndex >= 0)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _wellControllers[selectedWellIndex].text.trim().isEmpty
                      ? 'Well'
                      : _wellControllers[selectedWellIndex].text.trim(),
                  style: const TextStyle(
                    color: Color(0xFFCDA56A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                WwNumberField(
                  label: 'Beginning Oil Inventory',
                  controller: _oilInventoryWells[selectedWellIndex]
                      .beginningOilInventory,
                  helperText: 'BBL',
                  errorText: _errorTextFor(
                    _oilInventoryWells[selectedWellIndex].beginningOilInventory,
                  ),
                  onChanged: (_) {
                    _clearFieldIssue(
                      _oilInventoryWells[selectedWellIndex]
                          .beginningOilInventory,
                    );
                    setState(() {});
                  },
                ),
                WwNumberField(
                  label: 'Current Oil Inventory',
                  controller:
                      _oilInventoryWells[selectedWellIndex].currentOilInventory,
                  helperText: 'BBL',
                  errorText: _errorTextFor(
                    _oilInventoryWells[selectedWellIndex].currentOilInventory,
                  ),
                  onChanged: (_) {
                    setState(() {
                      _clearFieldIssue(
                        _oilInventoryWells[selectedWellIndex]
                            .currentOilInventory,
                      );
                      _syncComputedCushion(selectedWellIndex);
                    });
                  },
                ),
                WwNumberField(
                  label: 'Expected Oil Inventory',
                  controller: _oilInventoryWells[selectedWellIndex]
                      .expectedOilInventory,
                  helperText: 'BBL',
                  errorText: _errorTextFor(
                    _oilInventoryWells[selectedWellIndex].expectedOilInventory,
                  ),
                  onChanged: (_) {
                    setState(() {
                      _clearFieldIssue(
                        _oilInventoryWells[selectedWellIndex]
                            .expectedOilInventory,
                      );
                      _syncComputedCushion(selectedWellIndex);
                    });
                  },
                ),
                _buildCurrentCushionField(selectedWellIndex),
                const SizedBox(height: 4),
                _buildCushionStatus(selectedWellIndex),
                const SizedBox(height: 10),
                WwNumberField(
                  label: 'Maximum Cushion',
                  controller:
                      _oilInventoryWells[selectedWellIndex].maximumCushion,
                  helperText: 'BBL',
                  errorText: _errorTextFor(
                    _oilInventoryWells[selectedWellIndex].maximumCushion,
                  ),
                  onChanged: (_) {
                    setState(() {
                      _clearFieldIssue(
                        _oilInventoryWells[selectedWellIndex].maximumCushion,
                      );
                      _syncComputedCushion(selectedWellIndex);
                    });
                  },
                ),
              ],
            ),
          ),
        )
      else
        const Text(
          'No active wells. Start or edit a job to add well names.',
          style: TextStyle(color: Colors.white70),
        ),
    ]);
  }

  Widget _buildCurrentCushionField(int index) {
    final cushion = _oilInventoryWells[index].computedCushion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Current Cushion',
          helperText: 'BBL (Current Oil Inventory - Expected Oil Inventory)',
        ),
        child: Text(
          cushion.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFFCDA56A),
          ),
        ),
      ),
    );
  }

  Widget _buildCushionStatus(int index) {
    final well = _oilInventoryWells[index];
    final current = well.currentOilValue;
    final expected = well.expectedOilValue;
    final max = well.maximumCushionValue;
    final cushion = well.computedCushion;

    if (expected > current) {
      final byAmount = (expected - current).toStringAsFixed(2);
      return Text(
        'OUTSIDE CUSHION BY $byAmount BBL',
        style: const TextStyle(
          color: Color(0xFFE57373),
          fontWeight: FontWeight.w800,
        ),
      );
    }

    if (cushion >= 0 && cushion <= max) {
      return const Text(
        'WITHIN CUSHION',
        style: TextStyle(
          color: Color(0xFF7EDC8C),
          fontWeight: FontWeight.w800,
        ),
      );
    }

    final overBy = (cushion - max).toStringAsFixed(2);
    return Text(
      'OUTSIDE CUSHION BY $overBy BBL',
      style: const TextStyle(
        color: Color(0xFFE57373),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _contextValueTile({
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.trim().isEmpty ? '-' : value.trim(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productionContextSection() {
    final scheme = Theme.of(context).colorScheme;
    final selectedWellIndex = _resolvedSelectedWellIndex;
    return _section('Production Context', [
      Text(
        'Inventory is tied to the active production shift and current job.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _contextValueTile(label: 'Company', value: _company.text),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _contextValueTile(label: 'Pad', value: _pad.text),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _contextValueTile(label: 'Date', value: _date.text),
      const SizedBox(height: 12),
      Text(
        'Selected Well',
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      if (_wellControllers.isEmpty)
        Text(
          'No active wells. Start or edit a job to add well names.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: selectedWellIndex,
              decoration: const InputDecoration(labelText: 'Well'),
              items: [
                for (int i = 0; i < _wellControllers.length; i++)
                  DropdownMenuItem<int>(
                    value: i,
                    child: Text(
                      _wellControllers[i].text.trim().isEmpty
                          ? 'Well ${i + 1}'
                          : _wellControllers[i].text.trim(),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedWellIndex = value);
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                'Choke Type • ${_wellChokeTypes[selectedWellIndex]}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
    ]);
  }

  Widget _inventorySettingsSection() {
    return _section('Inventory Settings', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Sync Tank Count From Active Job'),
        subtitle: Text(
          _useJobSetupTanks
              ? 'ON: water and oil tank counts follow the active job.'
              : 'OFF: manage tank counts manually for this production shift.',
        ),
        value: _useJobSetupTanks,
        onChanged: (value) async {
          final activeJob = await _jobStorage.ensureActiveJobLoaded();
          setState(() {
            _useJobSetupTanks = value;
            if (value && activeJob != null) {
              _applyJobSetupDefaults(activeJob);
            }
          });
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _gaugeEntryType,
        decoration: const InputDecoration(labelText: 'Gauge Entry Type'),
        items: const [
          DropdownMenuItem(value: 'inches', child: Text('Inches')),
          DropdownMenuItem(value: 'feetInches', child: Text('Feet + Inches')),
          DropdownMenuItem(value: 'decimalFeet', child: Text('Decimal Feet')),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => _gaugeEntryType = value);
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _gasUnit,
        decoration: const InputDecoration(labelText: 'Gas Unit'),
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
        initialValue: _gasCalculationMethod,
        decoration: const InputDecoration(labelText: 'Gas Calculation Method'),
        items: const [
          DropdownMenuItem(
            value: 'accumulator',
            child: Text('Accumulator'),
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
        initialValue: _layoutProfileId,
        decoration: const InputDecoration(labelText: 'Layout Profile'),
        items: [
          for (final profile in _layoutProfiles)
            DropdownMenuItem(
              value: profile.id,
              child: Text(profile.name),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => _layoutProfileId = value);
        },
      ),
      if (widget.showManageLayoutsButton) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _manageLayouts,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Manage Report/Text Layouts'),
          ),
        ),
      ],
    ]);
  }

  Widget _content() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _validationCard(),
        _productionContextSection(),
        _inventorySettingsSection(),
        _tankSection(
          title: 'Starting Inventory • Water Tanks',
          tanks: _waterTanks,
          tankLabel: 'Water Tank',
        ),
        _tankSection(
          title: 'Starting Inventory • Oil Tanks',
          tanks: _oilTanks,
          tankLabel: 'Oil Tank',
        ),
        _oilInventorySection(),
        if (_gasCalculationMethod == 'accumulator')
          _section('Starting Gas', [
            WwNumberField(
              label: 'Starting Gas Accum',
              controller: _startingGasAccum,
              errorText: _errorTextFor(_startingGasAccum),
              onChanged: (_) {
                _clearFieldIssue(_startingGasAccum);
                setState(() {});
              },
            ),
          ]),
        _section('Pre-Round Adjustments', [
          WwNumberField(
            label: 'Water Hauled Before Round',
            controller: _waterHauledBeforeRound,
            errorText: _errorTextFor(_waterHauledBeforeRound),
            onChanged: (_) {
              _clearFieldIssue(_waterHauledBeforeRound);
              setState(() {});
            },
          ),
          WwNumberField(
            label: 'Oil Hauled Before Round',
            controller: _oilHauledBeforeRound,
            errorText: _errorTextFor(_oilHauledBeforeRound),
            onChanged: (_) {
              _clearFieldIssue(_oilHauledBeforeRound);
              setState(() {});
            },
          ),
          WwNumberField(
            label: 'Water Pumped Before Round',
            controller: _waterPumpedBeforeRound,
            errorText: _errorTextFor(_waterPumpedBeforeRound),
            onChanged: (_) {
              _clearFieldIssue(_waterPumpedBeforeRound);
              setState(() {});
            },
          ),
          WwNumberField(
            label: 'Oil Pumped Before Round',
            controller: _oilPumpedBeforeRound,
            errorText: _errorTextFor(_oilPumpedBeforeRound),
            onChanged: (_) {
              _clearFieldIssue(_oilPumpedBeforeRound);
              setState(() {});
            },
          ),
        ]),
        _runningTotalsSection(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveInventory,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Production Inventory'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _clearInventory,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Clear Inventory'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Scaffold(
        appBar: AppHeader(title: 'Tank Inventory', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.embedded) {
      return _content();
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Tank Inventory', showBack: true),
      body: _content(),
    );
  }
}

class _TankControllers {
  _TankControllers({
    required this.name,
    required this.gaugeInches,
    required this.gaugeFeet,
    required this.gaugeInchesPart,
    required this.gaugeDecimalFeet,
    required this.bblPerInch,
  });

  factory _TankControllers.fromTank(ProductionTank tank) {
    final entry = tank.gaugeEntry;
    return _TankControllers(
      name: TextEditingController(text: tank.name),
      gaugeInches: TextEditingController(
        text: entry.mode == 'inches' ? entry.inches : tank.gauge,
      ),
      gaugeFeet: TextEditingController(text: entry.feet),
      gaugeInchesPart: TextEditingController(text: entry.inchesPart),
      gaugeDecimalFeet: TextEditingController(text: entry.decimalFeet),
      bblPerInch: TextEditingController(text: tank.bblPerInch),
    );
  }

  final TextEditingController name;
  final TextEditingController gaugeInches;
  final TextEditingController gaugeFeet;
  final TextEditingController gaugeInchesPart;
  final TextEditingController gaugeDecimalFeet;
  final TextEditingController bblPerInch;

  ProductionGaugeEntry gaugeEntry(String mode) => ProductionGaugeEntry(
        mode: mode,
        inches: gaugeInches.text.trim(),
        feet: gaugeFeet.text.trim(),
        inchesPart: gaugeInchesPart.text.trim(),
        decimalFeet: gaugeDecimalFeet.text.trim(),
      );

  String convertedGaugeText(String mode) {
    final value = gaugeEntry(mode).asInches();
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  String gaugeEntryText(String mode) => gaugeEntry(mode).entryText();

  double calculatedBbl(String mode) {
    final gaugeValue = gaugeEntry(mode).asInches();
    final factor = double.tryParse(bblPerInch.text.trim()) ?? 1.67;
    final safeFactor = factor <= 0 ? 1.67 : factor;
    return gaugeValue * safeFactor;
  }

  ProductionTank toTank(String gaugeEntryType) {
    final factor = double.tryParse(bblPerInch.text.trim()) ?? 1.67;
    final safeFactor = factor <= 0 ? 1.67 : factor;
    final entry = gaugeEntry(gaugeEntryType);
    return ProductionTank(
      name: name.text.trim().isEmpty ? 'Tank' : name.text.trim(),
      gauge: convertedGaugeText(gaugeEntryType),
      gaugeEntry: entry,
      bblPerInch: safeFactor.toStringAsFixed(2),
    );
  }

  void dispose() {
    name.dispose();
    gaugeInches.dispose();
    gaugeFeet.dispose();
    gaugeInchesPart.dispose();
    gaugeDecimalFeet.dispose();
    bblPerInch.dispose();
  }
}

class _OilInventoryControllers {
  _OilInventoryControllers({
    required this.beginningOilInventory,
    required this.currentOilInventory,
    required this.expectedOilInventory,
    required this.currentCushion,
    required this.maximumCushion,
  });

  factory _OilInventoryControllers.blank() {
    return _OilInventoryControllers(
      beginningOilInventory: TextEditingController(),
      currentOilInventory: TextEditingController(),
      expectedOilInventory: TextEditingController(),
      currentCushion: TextEditingController(),
      maximumCushion: TextEditingController(),
    );
  }

  factory _OilInventoryControllers.fromWell({
    ProductionOilInventoryWell? existing,
  }) {
    final currentText = existing?.currentOilInventory ?? '';
    final expectedText = existing?.expectedOilInventory ?? '';
    final computed = _computeCushionFromStrings(currentText, expectedText);
    return _OilInventoryControllers(
      beginningOilInventory: TextEditingController(
        text: existing?.beginningOilInventory ?? '',
      ),
      currentOilInventory: TextEditingController(
        text: currentText,
      ),
      expectedOilInventory: TextEditingController(
        text: expectedText,
      ),
      currentCushion: TextEditingController(
        text: computed.toStringAsFixed(2),
      ),
      maximumCushion: TextEditingController(
        text: existing?.maximumCushion ?? '',
      ),
    );
  }

  factory _OilInventoryControllers.copyOf(
    _OilInventoryControllers source,
  ) {
    return _OilInventoryControllers(
      beginningOilInventory: TextEditingController(
        text: source.beginningOilInventory.text,
      ),
      currentOilInventory: TextEditingController(
        text: source.currentOilInventory.text,
      ),
      expectedOilInventory: TextEditingController(
        text: source.expectedOilInventory.text,
      ),
      currentCushion: TextEditingController(
        text: source.currentCushion.text,
      ),
      maximumCushion: TextEditingController(
        text: source.maximumCushion.text,
      ),
    );
  }

  final TextEditingController beginningOilInventory;
  final TextEditingController currentOilInventory;
  final TextEditingController expectedOilInventory;
  final TextEditingController currentCushion;
  final TextEditingController maximumCushion;

  static double _parse(String value) => double.tryParse(value.trim()) ?? 0;

  static double _computeCushionFromStrings(String current, String expected) {
    return _parse(current) - _parse(expected);
  }

  double get currentOilValue => _parse(currentOilInventory.text);
  double get expectedOilValue => _parse(expectedOilInventory.text);
  double get maximumCushionValue => _parse(maximumCushion.text);
  double get computedCushion => currentOilValue - expectedOilValue;

  void setComputedCushion() {
    currentCushion.text = computedCushion.toStringAsFixed(2);
  }

  ProductionOilInventoryWell toWell(String wellName) {
    return ProductionOilInventoryWell(
      wellName: wellName,
      beginningOilInventory: beginningOilInventory.text.trim(),
      currentOilInventory: currentOilInventory.text.trim(),
      expectedOilInventory: expectedOilInventory.text.trim(),
      currentCushion: computedCushion.toStringAsFixed(2),
      maximumCushion: maximumCushion.text.trim(),
    );
  }

  void dispose() {
    beginningOilInventory.dispose();
    currentOilInventory.dispose();
    expectedOilInventory.dispose();
    currentCushion.dispose();
    maximumCushion.dispose();
  }
}
