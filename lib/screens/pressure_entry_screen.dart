import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../models/round_reading.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/recovery_state_service.dart';
import '../services/round_storage_service.dart';
import '../utils/quick_round_reminder_utils.dart';
import 'shift_report_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/choke_selector_sheet.dart';
import '../widgets/ww_number_field.dart';

class PressureEntryScreen extends StatefulWidget {
  const PressureEntryScreen({super.key});

  @override
  State<PressureEntryScreen> createState() => _PressureEntryScreenState();
}

class _PressureEntryScreenState extends State<PressureEntryScreen> {
  static const _legacyInventoryKey = 'wellwerks_quick_round_start_inventory_v1';
  static const double _missingCalcValue = -1;

  final _service = ProductionShiftService();
  final _jobStorage = JobStorageService();
  final _roundStorage = RoundStorageService();
  final _settingsService = AppSettingsService();
  final _recoveryState = RecoveryStateService();
  bool _loading = true;
  bool _savingHour = false;
  int _activeHourIndex = 0;
  final Set<TextEditingController> _invalidHourControllers =
      <TextEditingController>{};
  String? _hourValidationMessage;
  bool _hourlyQuickRoundReminderEnabled = false;
  int _quickRoundReminderMinute = 0;
  AppSettingsData _settings = const AppSettingsData(
    defaultGasUnit: AppSettingsDefaults.gasUnit,
    defaultGaugeType: AppSettingsDefaults.gaugeType,
    defaultBblPerInch: AppSettingsDefaults.bblPerInch,
    defaultGasCalculationMethod: AppSettingsDefaults.gasCalculationMethod,
    defaultChokeDisplay: AppSettingsDefaults.chokeDisplay,
    defaultOptionalReportSections: AppSettingsDefaults.optionalReportSections,
  );

  late ProductionShift _shift;
  JobSetup? _activeJob;
  final List<_HourlyCheckControllers> _controllers = [];

  bool get _showVruSection => _settings.isOptionalSectionEnabled('vru');
  bool get _showFlareSection => _settings.isOptionalSectionEnabled('flare');
  bool get _showEcdSection => _settings.isOptionalSectionEnabled('ecd');
  bool get _showCompressorSection =>
      _settings.isOptionalSectionEnabled('compressor');
  bool get _showInventorySection =>
      _settings.isOptionalSectionEnabled('inventory');
  bool get _showNotesSection => _settings.isOptionalSectionEnabled('notes');

  static const List<String> _roundTimes = [
    '6 AM',
    '7 AM',
    '8 AM',
    '9 AM',
    '10 AM',
    '11 AM',
    'Noon',
    '1 PM',
    '2 PM',
    '3 PM',
    '4 PM',
    '5 PM',
    '6 PM',
    '7 PM',
    '8 PM',
    '9 PM',
    '10 PM',
    '11 PM',
    'Midnight',
    '1 AM',
    '2 AM',
    '3 AM',
    '4 AM',
    '5 AM',
  ];

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.quickRound);
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _load();
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    _load();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    var shift = await _service.loadActiveShift();
    shift = await _migrateLegacyInventory(shift);
    if (shift.inventory.productionRows.isEmpty && shift.savedRows.isNotEmpty) {
      shift = shift.copyWith(
        inventory: shift.inventory.copyWith(productionRows: shift.savedRows),
      );
      await _service.saveActiveShift(shift);
    }
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    final settings = await _settingsService.load();
    if (activeJob != null && shift.activeJobId != activeJob.id) {
      shift = shift.copyWith(activeJobId: activeJob.id);
      await _service.saveActiveShift(shift);
    }
    _shift = shift;
    _activeJob = activeJob;
    _rebuildControllers();
    final prefs = await SharedPreferences.getInstance();
    final savedReminderEnabled = prefs.getBool(
            RateTimerNotificationService.quickRoundReminderEnabledKey) ??
        false;
    final savedReminderMinute = normalizeQuickRoundReminderMinute(
      prefs.getInt(RateTimerNotificationService.quickRoundReminderMinuteKey) ??
          0,
    );
    if (!mounted) return;
    setState(() {
      _activeHourIndex = _firstIncompleteHourIndex();
      _settings = settings;
      _hourlyQuickRoundReminderEnabled = savedReminderEnabled;
      _quickRoundReminderMinute = savedReminderMinute;
      _loading = false;
    });
  }

  Future<void> _saveQuickRoundReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      RateTimerNotificationService.quickRoundReminderEnabledKey,
      _hourlyQuickRoundReminderEnabled,
    );
    await prefs.setInt(
      RateTimerNotificationService.quickRoundReminderMinuteKey,
      _quickRoundReminderMinute,
    );
  }

  void _showReminderMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setHourlyQuickRoundReminderEnabled(bool enabled) async {
    if (enabled == _hourlyQuickRoundReminderEnabled) return;

    if (!enabled) {
      await RateTimerNotificationService.instance.cancelQuickRoundReminder();
      if (!mounted) return;
      setState(() => _hourlyQuickRoundReminderEnabled = false);
      await _saveQuickRoundReminderSettings();
      _showReminderMessage('Quick Round reminder turned off.');
      return;
    }

    final granted = await RateTimerNotificationService.instance
        .requestNotificationPermission();
    if (!granted) {
      if (!mounted) return;
      setState(() => _hourlyQuickRoundReminderEnabled = false);
      await _saveQuickRoundReminderSettings();
      _showReminderMessage(
          'Notifications must be enabled for the Quick Round reminder.');
      return;
    }

    try {
      await RateTimerNotificationService.instance.scheduleQuickRoundReminder(
        minute: _quickRoundReminderMinute,
      );
      if (!mounted) return;
      setState(() => _hourlyQuickRoundReminderEnabled = true);
      await _saveQuickRoundReminderSettings();
      _showReminderMessage(
        'Quick Round reminder set for :${formatQuickRoundReminderMinute(_quickRoundReminderMinute)} every hour.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _hourlyQuickRoundReminderEnabled = false);
      await _saveQuickRoundReminderSettings();
      _showReminderMessage('Unable to enable Quick Round reminder. Try again.');
    }
  }

  Future<void> _pickQuickRoundReminderMinute() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Reminder Minute',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 420,
                  child: ListView.separated(
                    itemCount: 60,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, minute) {
                      final selected = minute == _quickRoundReminderMinute;
                      return Material(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).pop(minute),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  ':${formatQuickRoundReminderMinute(minute)}',
                                  style: TextStyle(
                                    color: selected
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                if (selected)
                                  Icon(
                                    Icons.check_circle,
                                    color: scheme.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    final nextMinute = normalizeQuickRoundReminderMinute(selected);
    final oldMinute = _quickRoundReminderMinute;

    setState(() => _quickRoundReminderMinute = nextMinute);
    await _saveQuickRoundReminderSettings();

    if (!_hourlyQuickRoundReminderEnabled) return;

    try {
      await RateTimerNotificationService.instance.scheduleQuickRoundReminder(
        minute: nextMinute,
      );
      _showReminderMessage(
        'Quick Round reminder set for :${formatQuickRoundReminderMinute(nextMinute)} every hour.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _quickRoundReminderMinute = oldMinute);
      await _saveQuickRoundReminderSettings();
      _showReminderMessage('Unable to update Quick Round reminder minute.');
    }
  }

  Widget _quickRoundReminderSetupCard() {
    final scheme = Theme.of(context).colorScheme;
    final minuteText =
        formatQuickRoundReminderMinute(_quickRoundReminderMinute);

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              value: _hourlyQuickRoundReminderEnabled,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Hourly Quick Round Reminder',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                _hourlyQuickRoundReminderEnabled
                    ? 'Every hour at :$minuteText'
                    : 'Off',
              ),
              onChanged: _setHourlyQuickRoundReminderEnabled,
            ),
            if (_hourlyQuickRoundReminderEnabled) ...[
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminder Minute'),
                subtitle: Text('Every hour at :$minuteText'),
                trailing: FilledButton(
                  onPressed: _pickQuickRoundReminderMinute,
                  child: Text(':$minuteText'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<ProductionShift> _migrateLegacyInventory(ProductionShift shift) async {
    if (shift.inventory.waterTanks.isNotEmpty &&
        shift.inventory.oilTanks.isNotEmpty &&
        shift.header.wells.isNotEmpty) {
      return shift;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyInventoryKey);
    if (raw == null || raw.isEmpty) return shift;
    final parts = raw.split('|');
    if (parts.length < 3) return shift;

    final migrated = shift.copyWith(
      inventory: shift.inventory.copyWith(
        waterTanks: [
          ProductionTank(
            name: 'Water Tank 1',
            gauge: parts[0],
            bblPerInch: parts[2].isEmpty ? '1.67' : parts[2],
          ),
        ],
        oilTanks: [
          ProductionTank(
            name: 'Oil Tank 1',
            gauge: parts[1],
            bblPerInch: parts[2].isEmpty ? '1.67' : parts[2],
          ),
        ],
        startingGasAccum: parts.length > 3 ? parts[3] : '',
      ),
      header: shift.header,
    );
    await _service.saveActiveShift(migrated);
    return migrated;
  }

  List<String> _fallbackWells() {
    final fromJob = (_activeJob?.resolvedWellNames ?? const <String>[])
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (fromJob.isNotEmpty) return fromJob;
    return _shift.header.wells.where((item) => item.trim().isNotEmpty).toList();
  }

  int? _placeholderWellIndex(String name) {
    final match =
        RegExp(r'^well\s*(\d+)$', caseSensitive: false).firstMatch(name.trim());
    if (match == null) return null;
    final parsed = int.tryParse(match.group(1) ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed - 1;
  }

  void _rebuildControllers() {
    final wells = _fallbackWells();
    if (wells.isEmpty) {
      _controllers
        ..forEach((controller) => controller.dispose())
        ..clear();
      return;
    }
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers
      ..clear()
      ..addAll(_shift.hourlyChecks.map(
        (check) => _HourlyCheckControllers.fromCheck(
          check: _normalizeCheck(check),
          wells: wells,
          waterTankCount: _shift.inventory.waterTanks.length,
          oilTankCount: _shift.inventory.oilTanks.length,
          gaugeEntryType: _shift.inventory.gaugeEntryType,
          chokeTypeForWell: _chokeTypeForWell,
        ),
      ));
  }

  ProductionHourlyCheck _normalizeCheck(ProductionHourlyCheck check) {
    final waterCount = _shift.inventory.waterTanks.length;
    final oilCount = _shift.inventory.oilTanks.length;
    final water = List<String>.from(check.waterTankGauges);
    final oil = List<String>.from(check.oilTankGauges);
    final waterEntries = List<ProductionGaugeEntry>.from(
      check.waterTankGaugeEntries,
    );
    final oilEntries = List<ProductionGaugeEntry>.from(
      check.oilTankGaugeEntries,
    );
    while (water.length < waterCount) {
      water.add('');
    }
    while (oil.length < oilCount) {
      oil.add('');
    }
    while (waterEntries.length < waterCount) {
      final fallback =
          waterEntries.length < water.length ? water[waterEntries.length] : '';
      waterEntries.add(ProductionGaugeEntry.fromLegacyGauge(fallback));
    }
    while (oilEntries.length < oilCount) {
      final fallback =
          oilEntries.length < oil.length ? oil[oilEntries.length] : '';
      oilEntries.add(ProductionGaugeEntry.fromLegacyGauge(fallback));
    }
    if (water.length > waterCount) {
      water.removeRange(waterCount, water.length);
    }
    if (oil.length > oilCount) {
      oil.removeRange(oilCount, oil.length);
    }
    if (waterEntries.length > waterCount) {
      waterEntries.removeRange(waterCount, waterEntries.length);
    }
    if (oilEntries.length > oilCount) {
      oilEntries.removeRange(oilCount, oilEntries.length);
    }
    final wells = _fallbackWells();
    if (wells.isEmpty) return check;
    final currentWell = check.well.trim();
    var normalizedWell = wells.contains(currentWell) ? currentWell : '';
    if (normalizedWell.isEmpty) {
      final placeholderIndex = _placeholderWellIndex(currentWell);
      if (placeholderIndex != null && placeholderIndex < wells.length) {
        normalizedWell = wells[placeholderIndex];
      }
    }
    if (normalizedWell.isEmpty) {
      normalizedWell = wells.first;
    }
    return check.copyWith(
      well: normalizedWell,
      chokeType: _chokeTypeForWell(normalizedWell),
      waterTankGauges: water,
      oilTankGauges: oil,
      waterTankGaugeEntries: waterEntries,
      oilTankGaugeEntries: oilEntries,
    );
  }

  Future<void> _persistShift() async {
    await _refreshActiveJobReference();
    final checks = _controllers.map((item) => item.toCheck()).toList();
    _shift = _shift.copyWith(hourlyChecks: checks);
    await _service.saveActiveShift(_shift);
  }

  int _firstIncompleteHourIndex() {
    if (_controllers.isEmpty) return 0;
    for (var i = 0; i < _controllers.length; i++) {
      if (!_isHourSaved(i)) {
        return i;
      }
    }
    return _controllers.length - 1;
  }

  List<String> get _activeWells => _fallbackWells();

  List<ProductionReportRow> get _storedRows {
    if (_shift.inventory.productionRows.isNotEmpty) {
      return _shift.inventory.productionRows;
    }
    return _shift.savedRows;
  }

  bool _gaugeEntryHasValue(ProductionGaugeEntry entry) {
    return entry.inches.trim().isNotEmpty ||
        entry.feet.trim().isNotEmpty ||
        entry.inchesPart.trim().isNotEmpty ||
        entry.decimalFeet.trim().isNotEmpty;
  }

  ProductionWellCheckData _wellDataForHour(int hourIndex, String well) {
    return _controllers[hourIndex].dataForWell(well, _chokeTypeForWell(well));
  }

  List<String> get _activeChemicals {
    final selected = _activeJob?.selectedChemicals ?? const <String>[];
    return selected;
  }

  bool _chemicalEnabled(String name) {
    return _activeChemicals
        .any((item) => item.toLowerCase() == name.toLowerCase());
  }

  Iterable<String> _chemicalValues(ProductionWellCheckData data) sync* {
    if (_chemicalEnabled('Biocide')) yield data.biocide;
    if (_chemicalEnabled('Scavenger')) yield data.scavenger;
    if (_chemicalEnabled('Defoamer')) yield data.defoamer;
    if (_chemicalEnabled('Scale Inhibitor')) yield data.scaleInhibitor;
  }

  bool _isWellEntered(int hourIndex, String well) {
    final data = _wellDataForHour(hourIndex, well);
    final hasScalarValue = [
      data.hoursSincePrevious,
      data.choke,
      data.tbg,
      data.icp,
      data.csg,
      data.currentGasAccum,
      data.salesGasRate,
      data.gasStatic,
      data.gasDifferential,
      data.gasTemp,
      data.waterSpecificGravity,
      data.wellheadTemp,
      data.waterTemp,
      if (_showFlareSection) data.flareRate,
      if (_showFlareSection) data.flarePilotTemp,
      ..._chemicalValues(data),
      if (_showVruSection) data.vruGasRate,
      if (_showCompressorSection) data.compressorInjection,
      if (_showVruSection) data.vruSuction,
      if (_showVruSection) data.vruDischarge,
      if (_showInventorySection) data.waterHauled,
      if (_showInventorySection) data.oilHauled,
      if (_showInventorySection) data.waterPumped,
      if (_showInventorySection) data.oilPumped,
      data.sandRate,
      if (_showNotesSection) data.notes,
    ].any((value) => value.trim().isNotEmpty);

    final hasGaugeValue = data.waterTankGaugeEntries.any(_gaugeEntryHasValue) ||
        data.oilTankGaugeEntries.any(_gaugeEntryHasValue);

    return hasScalarValue || hasGaugeValue;
  }

  bool _isHourSaved(int hourIndex) {
    return _storedRows.any((row) => row.hourIndex == hourIndex);
  }

  Future<void> _refreshActiveJobReference() async {
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    _activeJob = activeJob;
    final activeJobId = activeJob?.id;
    if (activeJobId == null || _shift.activeJobId == activeJobId) {
      return;
    }
    _shift = _shift.copyWith(activeJobId: activeJobId);
  }

  double _n(String value) => ProductionMath.parse(value);

  bool get _useGasAccumulator =>
      _shift.inventory.gasCalculationMethod == 'accumulator';

  bool get _useStartingReadings => _shift.inventory.useStartingReadings;

  bool _hasCompleteControllerGaugeEntries(
      List<_GaugeEntryControllers> entries) {
    return entries.isNotEmpty &&
        entries.every(
          (item) =>
              _gaugeEntryHasValue(item.entry(_shift.inventory.gaugeEntryType)),
        );
  }

  bool _hasCompleteDataGaugeEntries(List<ProductionGaugeEntry> entries) {
    return entries.isNotEmpty && entries.every(_gaugeEntryHasValue);
  }

  bool _hasStartingWaterReading() {
    if (_shift.inventory.waterTanks.isEmpty) return false;
    return _gaugeEntryHasValue(_shift.inventory.waterTanks.first.gaugeEntry);
  }

  bool _hasStartingOilReading() {
    if (_shift.inventory.oilTanks.isEmpty) return false;
    return _gaugeEntryHasValue(_shift.inventory.oilTanks.first.gaugeEntry);
  }

  bool _isMissingCalc(double value) => value < 0;

  ProductionReportRow? _latestSavedBeforeWith(
    int index,
    String well,
    bool Function(ProductionReportRow row) predicate,
  ) {
    final previous = _storedRows
        .where(
          (row) => row.well == well && row.hourIndex < index && predicate(row),
        )
        .toList()
      ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
    if (previous.isEmpty) return null;
    return previous.last;
  }

  double _startingWaterBaselineOrMissing() {
    if (!_useStartingReadings || !_hasStartingWaterReading()) {
      return double.nan;
    }
    final value = _startingWaterBbl();
    return value > 0 ? value : double.nan;
  }

  double _startingOilBaselineOrMissing() {
    if (!_useStartingReadings || !_hasStartingOilReading()) {
      return double.nan;
    }
    final value = _startingOilBbl();
    return value > 0 ? value : double.nan;
  }

  double _startingGasBaselineOrMissing() {
    if (!_useStartingReadings ||
        _shift.inventory.startingGasAccum.trim().isEmpty) {
      return double.nan;
    }
    final value = _startingGasAccum();
    return value >= 0 ? value : double.nan;
  }

  bool _canUseWaterBaseline(int index, String well) {
    if (index == 0) {
      return _useStartingReadings && _hasStartingWaterReading();
    }
    return _latestSavedBefore(index, well) != null;
  }

  bool _canUseOilBaseline(int index, String well) {
    if (index == 0) {
      return _useStartingReadings && _hasStartingOilReading();
    }
    return _latestSavedBefore(index, well) != null;
  }

  bool _canUseGasBaseline(int index, String well) {
    if (!_useGasAccumulator) {
      return _controllers[index].salesGasRate.text.trim().isNotEmpty;
    }
    if (_controllers[index].currentGasAccum.text.trim().isEmpty) {
      return false;
    }
    if (index == 0) {
      return _useStartingReadings &&
          _shift.inventory.startingGasAccum.trim().isNotEmpty;
    }
    return _latestSavedBefore(index, well) != null;
  }

  void _setUseStartingReadings(bool enabled) {
    setState(() {
      _shift = _shift.copyWith(
        inventory: _shift.inventory.copyWith(useStartingReadings: enabled),
      );
    });
    _service.saveActiveShift(_shift);
  }

  void _setStartingGasAccum(String value) {
    setState(() {
      _shift = _shift.copyWith(
        inventory: _shift.inventory.copyWith(startingGasAccum: value),
      );
    });
    _service.saveActiveShift(_shift);
  }

  void _setStartingWaterTank(String value) {
    if (_shift.inventory.waterTanks.isEmpty) return;
    final tanks = List<ProductionTank>.from(_shift.inventory.waterTanks);
    tanks[0] = tanks[0].copyWith(
      gauge: value,
      gaugeEntry: ProductionGaugeEntry.fromLegacyGauge(value),
    );
    setState(() {
      _shift = _shift.copyWith(
        inventory: _shift.inventory.copyWith(waterTanks: tanks),
      );
    });
    _service.saveActiveShift(_shift);
  }

  void _setStartingOilTank(String value) {
    if (_shift.inventory.oilTanks.isEmpty) return;
    final tanks = List<ProductionTank>.from(_shift.inventory.oilTanks);
    tanks[0] = tanks[0].copyWith(
      gauge: value,
      gaugeEntry: ProductionGaugeEntry.fromLegacyGauge(value),
    );
    setState(() {
      _shift = _shift.copyWith(
        inventory: _shift.inventory.copyWith(oilTanks: tanks),
      );
    });
    _service.saveActiveShift(_shift);
  }

  String get _gasUnitLabel =>
      _shift.inventory.gasUnit == 'mmcfd' ? 'mmcf/d' : 'mcf/d';

  double _displayGasToBase(String value) {
    final parsed = _n(value);
    return _shift.inventory.gasUnit == 'mmcfd' ? parsed * 1000 : parsed;
  }

  double _baseGasToDisplay(double value) {
    return _shift.inventory.gasUnit == 'mmcfd' ? value / 1000 : value;
  }

  String _storeGasField(String value) {
    if (value.trim().isEmpty) return '';
    final base = _displayGasToBase(value);
    return base % 1 == 0 ? base.toStringAsFixed(0) : base.toStringAsFixed(3);
  }

  String _chokeTypeForWell(String well) {
    return _shift.header.wellChokeTypes[well] ?? _shift.header.chokeType;
  }

  String _formatChk(String chokeValue, String chokeType) {
    final value = chokeValue.trim();
    if (value.isEmpty) return '-';
    return 'CHK - $value $chokeType';
  }

  String _fmt(double value) {
    final rounded = value.abs() < 0.01 ? 0 : value;
    return rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  String _timeAtOffset(int offset) {
    final start = _roundTimes.indexOf(_shift.roundStartTime);
    final startIndex = start < 0 ? 0 : start;
    return _roundTimes[(startIndex + offset) % _roundTimes.length];
  }

  List<ProductionHourlyCheck> _buildBlankChecks() {
    final wells = _activeWells;
    if (wells.isEmpty) {
      return const <ProductionHourlyCheck>[];
    }
    return List<ProductionHourlyCheck>.generate(
      _shift.checkCount,
      (index) => ProductionHourlyCheck(
        time: _timeAtOffset(index),
        well: wells.first,
        chokeType: _chokeTypeForWell(wells.first),
        waterTankGauges:
            List<String>.filled(_shift.inventory.waterTanks.length, ''),
        oilTankGauges:
            List<String>.filled(_shift.inventory.oilTanks.length, ''),
      ),
    );
  }

  Future<void> _buildRound() async {
    await _refreshActiveJobReference();
    final updated = _shift.copyWith(
      activeJobId: _activeJob?.id ?? _shift.activeJobId,
      hourlyChecks: _buildBlankChecks(),
      savedRows: const [],
      inventory: _shift.inventory.copyWith(productionRows: const []),
      clearSelectedTextHour: true,
    );
    _shift = updated;
    _rebuildControllers();
    await _service.saveActiveShift(updated);
    if (!mounted) return;
    setState(() => _activeHourIndex = 0);
  }

  Future<void> _clearRoundWithConfirm() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Round?'),
            content: const Text(
              'This clears the built round, hourly checks, and production report rows but keeps the saved Production Inventory baseline.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Round'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await _refreshActiveJobReference();
    _shift = _shift.copyWith(
      activeJobId: _activeJob?.id ?? _shift.activeJobId,
      hourlyChecks: const [],
      savedRows: const [],
      inventory: _shift.inventory.copyWith(productionRows: const []),
      clearSelectedTextHour: true,
    );
    _rebuildControllers();
    await _service.saveActiveShift(_shift);
    if (!mounted) return;
    setState(() => _activeHourIndex = 0);
  }

  ProductionReportRow? _latestSavedBefore(int index, String well) {
    final previous = _storedRows
        .where((row) => row.well == well && row.hourIndex < index)
        .toList()
      ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
    if (previous.isEmpty) return null;
    return previous.last;
  }

  double _startingWaterBbl() {
    return ProductionMath.totalTankBbl(
      _shift.inventory.waterTanks,
      _shift.inventory.waterTanks
          .map((tank) => tank.gaugeEntry.asInches().toString())
          .toList(),
    );
  }

  double _startingOilBbl() {
    return ProductionMath.totalTankBbl(
      _shift.inventory.oilTanks,
      _shift.inventory.oilTanks
          .map((tank) => tank.gaugeEntry.asInches().toString())
          .toList(),
    );
  }

  double _startingGasAccum() => _n(_shift.inventory.startingGasAccum);

  double _currentWaterBbl(int index) {
    final controller = _controllers[index];
    if (!_hasCompleteControllerGaugeEntries(controller.waterTankGaugeEntries)) {
      return double.nan;
    }
    return ProductionMath.totalTankBbl(
      _shift.inventory.waterTanks,
      controller.waterTankGaugeEntries
          .map((item) =>
              item.entry(_shift.inventory.gaugeEntryType).asInches().toString())
          .toList(),
    );
  }

  double _currentOilBbl(int index) {
    final controller = _controllers[index];
    if (!_hasCompleteControllerGaugeEntries(controller.oilTankGaugeEntries)) {
      return double.nan;
    }
    return ProductionMath.totalTankBbl(
      _shift.inventory.oilTanks,
      controller.oilTankGaugeEntries
          .map((item) =>
              item.entry(_shift.inventory.gaugeEntryType).asInches().toString())
          .toList(),
    );
  }

  double _previousWaterBbl(int index) {
    final previous = _latestSavedBefore(index, _controllers[index].well);
    if (previous == null) {
      if (_canUseWaterBaseline(index, _controllers[index].well)) {
        return _startingWaterBbl();
      }
      return double.nan;
    }
    return previous.currentWaterBbl;
  }

  double _previousOilBbl(int index) {
    final previous = _latestSavedBefore(index, _controllers[index].well);
    if (previous == null) {
      if (_canUseOilBaseline(index, _controllers[index].well)) {
        return _startingOilBbl();
      }
      return double.nan;
    }
    return previous.currentOilBbl;
  }

  double _previousGasAccum(int index) {
    final previous = _latestSavedBefore(index, _controllers[index].well);
    if (previous == null) {
      if (_canUseGasBaseline(index, _controllers[index].well)) {
        return _startingGasAccum();
      }
      return double.nan;
    }
    return previous.currentGasAccum;
  }

  double _hourlyGas(int index) {
    final currentWell = _controllers[index].well;
    final hasPrevious = _latestSavedBefore(index, currentWell) != null;
    if (!hasPrevious) {
      return double.nan;
    }
    final intervalHours =
        double.tryParse(_controllers[index].hoursSincePrevious.text.trim()) ??
            0;
    if (intervalHours <= 0) {
      return double.nan;
    }

    if (!_useGasAccumulator) {
      if (_controllers[index].salesGasRate.text.trim().isEmpty) {
        return double.nan;
      }
      final gasRate = _displayGasToBase(_controllers[index].salesGasRate.text);
      return gasRate / 24;
    }
    final previous = _previousGasAccum(index);
    if (previous.isNaN) {
      return double.nan;
    }
    final intervalGas = ProductionMath.hourlyGas(
      currentGasAccum: _n(_controllers[index].currentGasAccum.text),
      previousGasAccum: previous,
    );
    return intervalGas / intervalHours;
  }

  double _gas24Hour(int index) {
    final hourly = _hourlyGas(index);
    if (hourly.isNaN) {
      return double.nan;
    }
    if (!_useGasAccumulator) {
      return _displayGasToBase(_controllers[index].salesGasRate.text);
    }
    return ProductionMath.gas24Hour(hourly);
  }

  double _waterProduction(int index) {
    final check = _controllers[index];
    final currentWell = check.well;
    final hasPrevious = _latestSavedBefore(index, currentWell) != null;
    if (!hasPrevious) {
      return double.nan;
    }
    final intervalHours =
        double.tryParse(check.hoursSincePrevious.text.trim()) ?? 0;
    if (intervalHours <= 0) {
      return double.nan;
    }

    final current = _currentWaterBbl(index);
    final previous = _previousWaterBbl(index);
    if (current.isNaN || previous.isNaN) {
      return double.nan;
    }
    final intervalVolume = ProductionMath.waterProduction(
      currentWaterBbl: current,
      previousWaterBbl: previous,
      waterHauled: _n(check.waterHauled.text),
      waterPumped: _n(check.waterPumped.text),
      preRoundWaterHauled: 0,
      preRoundWaterPumped: 0,
      isFirstHour: false,
    );
    if (intervalVolume < 0) {
      return double.nan;
    }
    return (intervalVolume / intervalHours)
        .clamp(0, double.infinity)
        .toDouble();
  }

  double _oilProduction(int index) {
    final check = _controllers[index];
    final currentWell = check.well;
    final hasPrevious = _latestSavedBefore(index, currentWell) != null;
    if (!hasPrevious) {
      return double.nan;
    }
    final intervalHours =
        double.tryParse(check.hoursSincePrevious.text.trim()) ?? 0;
    if (intervalHours <= 0) {
      return double.nan;
    }

    final current = _currentOilBbl(index);
    final previous = _previousOilBbl(index);
    if (current.isNaN || previous.isNaN) {
      return double.nan;
    }
    final intervalVolume = ProductionMath.oilProduction(
      currentOilBbl: current,
      previousOilBbl: previous,
      oilHauled: _n(check.oilHauled.text),
      oilPumped: _n(check.oilPumped.text),
      preRoundOilHauled: 0,
      preRoundOilPumped: 0,
      isFirstHour: false,
    );
    if (intervalVolume < 0) {
      return double.nan;
    }
    return (intervalVolume / intervalHours)
        .clamp(0, double.infinity)
        .toDouble();
  }

  String _gaugeText(
    List<ProductionTank> tanks,
    List<ProductionGaugeEntry> gauges,
  ) {
    final parts = <String>[];
    for (var i = 0; i < tanks.length; i++) {
      final entry = gauges[i];
      final converted = entry.asInches();
      final convertedText = converted % 1 == 0
          ? converted.toStringAsFixed(0)
          : converted.toStringAsFixed(2);
      parts.add(
        '${tanks[i].name}: ${entry.entryText()} ($convertedText in)',
      );
    }
    return parts.join(', ');
  }

  double _currentWaterBblForData(ProductionWellCheckData data) {
    if (!_hasCompleteDataGaugeEntries(data.waterTankGaugeEntries)) {
      return _missingCalcValue;
    }
    return ProductionMath.totalTankBbl(
      _shift.inventory.waterTanks,
      data.waterTankGaugeEntries
          .map((item) => item.asInches().toString())
          .toList(),
    );
  }

  double _currentOilBblForData(ProductionWellCheckData data) {
    if (!_hasCompleteDataGaugeEntries(data.oilTankGaugeEntries)) {
      return _missingCalcValue;
    }
    return ProductionMath.totalTankBbl(
      _shift.inventory.oilTanks,
      data.oilTankGaugeEntries
          .map((item) => item.asInches().toString())
          .toList(),
    );
  }

  double _parseCushionBbl(String value) {
    return double.tryParse(value.trim()) ?? double.nan;
  }

  double _expectedOilInventoryForData(ProductionWellCheckData data) {
    return _parseCushionBbl(data.expectedOilInventory);
  }

  double _maximumCushionForData(ProductionWellCheckData data) {
    final parsed = _parseCushionBbl(data.maximumCushion);
    return parsed.isNaN || parsed < 0 ? 0 : parsed;
  }

  double _currentCushionForData(ProductionWellCheckData data) {
    final current = _currentOilBblForData(data);
    final expected = _expectedOilInventoryForData(data);
    if (_isMissingCalc(current) || current.isNaN || expected.isNaN) {
      return _missingCalcValue;
    }
    return current - expected;
  }

  String _fmtCushion(double value) {
    if (value.isNaN || _isMissingCalc(value)) return '--';
    if (value.abs() < 0.01) return '0';
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  Widget _oilCushionSection(int index) {
    final data = _controllers[index].dataForWell(
      _controllers[index].well,
      _chokeTypeForWell(_controllers[index].well),
    );
    final current = _currentOilBblForData(data);
    final expected = _expectedOilInventoryForData(data);
    final maximum = _maximumCushionForData(data);
    final cushion = _currentCushionForData(data);
    final hasCurrent = !_isMissingCalc(current) && !current.isNaN;
    final hasExpected = !expected.isNaN;
    final hasCushion = !_isMissingCalc(cushion) && !cushion.isNaN;
    final withinCushion = hasCushion && cushion >= 0 && cushion <= maximum;
    final outsideAmount = hasCushion
        ? (cushion < 0 ? cushion.abs() : (cushion - maximum).abs())
        : double.nan;

    return _section('Oil Cushion', [
      WwNumberField(
        label: 'Beginning Oil Inventory (BBL)',
        controller: _controllers[index].beginningOilInventory,
        onChanged: (_) {
          setState(() {});
          _persistShift();
        },
      ),
      const SizedBox(height: 2),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Current Oil Inventory (BBL)',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            Text(
              hasCurrent ? _fmt(current) : '--',
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      WwNumberField(
        label: 'Expected Oil Inventory (BBL)',
        controller: _controllers[index].expectedOilInventory,
        onChanged: (_) {
          setState(() {});
          _persistShift();
        },
      ),
      WwNumberField(
        label: 'Maximum Cushion (BBL)',
        controller: _controllers[index].maximumCushion,
        onChanged: (_) {
          setState(() {});
          _persistShift();
        },
      ),
      const SizedBox(height: 4),
      if (hasCushion && cushion >= 0) ...[
        Text(
          'Current Cushion (BBL): ${_fmtCushion(cushion)}',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
      ],
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              withinCushion ? const Color(0xFF12351E) : const Color(0xFF3A1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: withinCushion
                ? const Color(0xFF55D980)
                : const Color(0xFFFF6B6B),
          ),
        ),
        child: Text(
          !hasCurrent || !hasExpected
              ? 'Enter expected oil inventory to calculate Cushion.'
              : withinCushion
                  ? '🟢 WITHIN CUSHION'
                  : '🔴 OUTSIDE CUSHION BY ${_fmtCushion(outsideAmount)} BBL',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ]);
  }

  double _hourlyGasForData(
      int index, ProductionWellCheckData data, String well) {
    final previous = _latestSavedBefore(index, well);
    if (previous == null) {
      return _missingCalcValue;
    }
    final intervalHours =
        double.tryParse(data.hoursSincePrevious.trim()) ?? _missingCalcValue;
    if (_isMissingCalc(intervalHours) || intervalHours <= 0) {
      return _missingCalcValue;
    }
    if (!_useGasAccumulator) {
      if (data.salesGasRate.trim().isEmpty) {
        return _missingCalcValue;
      }
      final gasRate = _displayGasToBase(data.salesGasRate);
      return gasRate / 24;
    }
    final previousGasAccum = _latestSavedBeforeWith(
          index,
          well,
          (row) =>
              !_isMissingCalc(row.currentGasAccum) && row.currentGasAccum > 0,
        )?.currentGasAccum ??
        _startingGasBaselineOrMissing();
    if (previousGasAccum.isNaN || data.currentGasAccum.trim().isEmpty) {
      return _missingCalcValue;
    }
    final current = _n(data.currentGasAccum);
    if (current < previousGasAccum) {
      return _missingCalcValue;
    }
    final intervalGas = ProductionMath.hourlyGas(
      currentGasAccum: current,
      previousGasAccum: previousGasAccum,
    );
    return intervalGas / intervalHours;
  }

  double _gas24HourForData(
      int index, ProductionWellCheckData data, String well) {
    final hourly = _hourlyGasForData(index, data, well);
    if (_isMissingCalc(hourly)) {
      return _missingCalcValue;
    }
    if (!_useGasAccumulator) {
      return _displayGasToBase(data.salesGasRate);
    }
    return ProductionMath.gas24Hour(hourly);
  }

  double _waterProductionForData(
      int index, ProductionWellCheckData data, String well) {
    final previousRow = _latestSavedBefore(index, well);
    if (previousRow == null) {
      return _missingCalcValue;
    }
    final intervalHours =
        double.tryParse(data.hoursSincePrevious.trim()) ?? _missingCalcValue;
    if (_isMissingCalc(intervalHours) || intervalHours <= 0) {
      return _missingCalcValue;
    }

    final previous = _latestSavedBeforeWith(
          index,
          well,
          (row) =>
              !_isMissingCalc(row.currentWaterBbl) && row.currentWaterBbl > 0,
        )?.currentWaterBbl ??
        _startingWaterBaselineOrMissing();
    final current = _currentWaterBblForData(data);
    if (previous.isNaN || _isMissingCalc(current) || current <= 0) {
      return _missingCalcValue;
    }
    final intervalVolume = ProductionMath.waterProduction(
      currentWaterBbl: current,
      previousWaterBbl: previous,
      waterHauled: _n(data.waterHauled),
      waterPumped: _n(data.waterPumped),
      preRoundWaterHauled: 0,
      preRoundWaterPumped: 0,
      isFirstHour: false,
    );
    if (intervalVolume < 0) {
      return _missingCalcValue;
    }
    return intervalVolume / intervalHours;
  }

  double _oilProductionForData(
      int index, ProductionWellCheckData data, String well) {
    final previousRow = _latestSavedBefore(index, well);
    if (previousRow == null) {
      return _missingCalcValue;
    }
    final intervalHours =
        double.tryParse(data.hoursSincePrevious.trim()) ?? _missingCalcValue;
    if (_isMissingCalc(intervalHours) || intervalHours <= 0) {
      return _missingCalcValue;
    }

    final previous = _latestSavedBeforeWith(
          index,
          well,
          (row) => !_isMissingCalc(row.currentOilBbl) && row.currentOilBbl > 0,
        )?.currentOilBbl ??
        _startingOilBaselineOrMissing();
    final current = _currentOilBblForData(data);
    if (previous.isNaN || _isMissingCalc(current) || current <= 0) {
      return _missingCalcValue;
    }
    final intervalVolume = ProductionMath.oilProduction(
      currentOilBbl: current,
      previousOilBbl: previous,
      oilHauled: _n(data.oilHauled),
      oilPumped: _n(data.oilPumped),
      preRoundOilHauled: 0,
      preRoundOilPumped: 0,
      isFirstHour: false,
    );
    if (intervalVolume < 0) {
      return _missingCalcValue;
    }
    return intervalVolume / intervalHours;
  }

  ProductionReportRow _buildRowForWell(
    int hourIndex,
    String well,
    ProductionWellCheckData data,
  ) {
    final waterProduction = _waterProductionForData(hourIndex, data, well);
    final oilProduction = _oilProductionForData(hourIndex, data, well);
    final gas24HourRate = _gas24HourForData(hourIndex, data, well);
    final hourlyGas = _hourlyGasForData(hourIndex, data, well);
    final currentWaterBbl = _currentWaterBblForData(data);
    final currentOilBbl = _currentOilBblForData(data);
    final currentGasAccum = _useGasAccumulator
        ? (data.currentGasAccum.trim().isEmpty
            ? _missingCalcValue
            : _n(data.currentGasAccum))
        : (_latestSavedBeforeWith(
              hourIndex,
              well,
              (row) =>
                  !_isMissingCalc(row.currentGasAccum) &&
                  row.currentGasAccum > 0,
            )?.currentGasAccum ??
            (() {
              final starting = _startingGasBaselineOrMissing();
              return starting.isNaN ? _missingCalcValue : starting;
            })());
    return ProductionReportRow(
      hourIndex: hourIndex,
      time: _controllers[hourIndex].time,
      well: well,
      choke: data.choke.trim(),
      chokeType: _chokeTypeForWell(well),
      tbg: data.tbg.trim(),
      icp: data.icp.trim(),
      csg: data.csg.trim(),
      waterProduction: waterProduction,
      oilProduction: oilProduction,
      hourlyGas: hourlyGas,
      gas24HourRate: gas24HourRate,
      salesGasRate: gas24HourRate,
      gasStatic: data.gasStatic.trim(),
      gasDifferential: data.gasDifferential.trim(),
      gasTemp: data.gasTemp.trim(),
      waterSpecificGravity: data.waterSpecificGravity.trim(),
      wellheadTemp: data.wellheadTemp.trim(),
      waterTemp: data.waterTemp.trim(),
      flareRate: _showFlareSection ? _storeGasField(data.flareRate) : '',
      flarePilotTemp: _showFlareSection ? data.flarePilotTemp.trim() : '',
      biocide: _chemicalEnabled('Biocide') ? data.biocide.trim() : '',
      scavenger: _chemicalEnabled('Scavenger') ? data.scavenger.trim() : '',
      defoamer: _chemicalEnabled('Defoamer') ? data.defoamer.trim() : '',
      scaleInhibitor:
          _chemicalEnabled('Scale Inhibitor') ? data.scaleInhibitor.trim() : '',
      vruGasRate: _showVruSection ? _storeGasField(data.vruGasRate) : '',
      compressorInjection: _showCompressorSection
          ? _storeGasField(data.compressorInjection)
          : '',
      vruSuction: _showVruSection ? data.vruSuction.trim() : '',
      vruDischarge: _showVruSection ? data.vruDischarge.trim() : '',
      sandRate: data.sandRate.trim(),
      waterGaugeText:
          _gaugeText(_shift.inventory.waterTanks, data.waterTankGaugeEntries),
      oilGaugeText:
          _gaugeText(_shift.inventory.oilTanks, data.oilTankGaugeEntries),
      currentWaterBbl: currentWaterBbl,
      currentOilBbl: currentOilBbl,
      currentGasAccum: currentGasAccum,
      hoursSincePrevious: double.tryParse(data.hoursSincePrevious.trim()) ?? 0,
      waterHauled: _showInventorySection ? _n(data.waterHauled) : 0,
      oilHauled: _showInventorySection ? _n(data.oilHauled) : 0,
      waterPumped: _showInventorySection ? _n(data.waterPumped) : 0,
      oilPumped: _showInventorySection ? _n(data.oilPumped) : 0,
      notes: _showNotesSection ? data.notes.trim() : '',
    );
  }

  Future<void> _saveActiveHour() async {
    final hourIndex = _activeHourIndex;
    final current = _controllers[hourIndex];
    final enteredWells =
        _activeWells.where((well) => _isWellEntered(hourIndex, well)).toList();

    final invalidControllers = <TextEditingController>{};
    void disallowNegative(TextEditingController controller) {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      final value = double.tryParse(text);
      if (value != null && value < 0) {
        invalidControllers.add(controller);
      }
    }

    for (final controller in [
      current.hoursSincePrevious,
      current.choke,
      current.tbg,
      current.icp,
      current.csg,
      current.currentGasAccum,
      current.salesGasRate,
      current.gasStatic,
      current.gasDifferential,
      current.waterSpecificGravity,
      if (_showFlareSection) current.flareRate,
      if (_chemicalEnabled('Biocide')) current.biocide,
      if (_chemicalEnabled('Scavenger')) current.scavenger,
      if (_chemicalEnabled('Defoamer')) current.defoamer,
      if (_chemicalEnabled('Scale Inhibitor')) current.scaleInhibitor,
      if (_showVruSection) current.vruGasRate,
      if (_showCompressorSection) current.compressorInjection,
      if (_showVruSection) current.vruSuction,
      if (_showVruSection) current.vruDischarge,
      if (_showInventorySection) current.waterHauled,
      if (_showInventorySection) current.oilHauled,
      if (_showInventorySection) current.waterPumped,
      if (_showInventorySection) current.oilPumped,
      current.sandRate,
      current.beginningOilInventory,
      current.expectedOilInventory,
      current.maximumCushion,
      ...current.waterTankGaugeEntries.expand((item) => item.controllers),
      ...current.oilTankGaugeEntries.expand((item) => item.controllers),
    ]) {
      disallowNegative(controller);
    }

    setState(() {
      _invalidHourControllers
        ..clear()
        ..addAll(invalidControllers);
      _hourValidationMessage = invalidControllers.isNotEmpty
          ? 'Negative values are not valid in the highlighted production fields.'
          : null;
    });

    if (enteredWells.isEmpty) {
      setState(() {
        _hourValidationMessage =
            'Enter at least one value before saving this hour.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter at least one value before saving this hour.'),
        ),
      );
      return;
    }

    final wellsMissingHours = <String>[];
    for (final well in enteredWells) {
      final hasPrevious = _latestSavedBefore(hourIndex, well) != null;
      if (!hasPrevious) continue;
      final data = _wellDataForHour(hourIndex, well);
      final hours = double.tryParse(data.hoursSincePrevious.trim()) ?? 0;
      if (hours <= 0) {
        wellsMissingHours.add(well);
      }
    }

    if (wellsMissingHours.isNotEmpty) {
      final message =
          'Enter Hours Since Previous Reading for: ${wellsMissingHours.join(', ')}';
      setState(() => _hourValidationMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    if (invalidControllers.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_hourValidationMessage!)),
      );
      return;
    }

    await _persistShift();
    final rows = <ProductionReportRow>[
      for (final well in enteredWells)
        _buildRowForWell(hourIndex, well, _wellDataForHour(hourIndex, well)),
    ];

    final warnings = <String>[];
    for (final row in rows) {
      final previousData = _latestSavedWellData(hourIndex, row.well);
      if (row.waterProduction.abs() > 250) {
        warnings.add('${row.well} water rate is unusually large.');
      }
      if (row.oilProduction.abs() > 250) {
        warnings.add('${row.well} oil rate is unusually large.');
      }
      final currentSand = double.tryParse(
              _wellDataForHour(hourIndex, row.well).sandRate.trim()) ??
          0;
      if (currentSand.abs() > 100) {
        warnings.add('${row.well} sand rate is unusually large.');
      }
      if (previousData != null) {
        void comparePressure(
            String label, String currentText, String previousText) {
          final currentValue = double.tryParse(currentText.trim());
          final previousValue = double.tryParse(previousText.trim());
          if (currentValue != null &&
              previousValue != null &&
              (currentValue - previousValue).abs() > 1000) {
            warnings.add('${row.well} $label changed by more than 1000 PSI.');
          }
        }

        comparePressure(
            'TBG', _wellDataForHour(hourIndex, row.well).tbg, previousData.tbg);
        comparePressure(
            'ICP', _wellDataForHour(hourIndex, row.well).icp, previousData.icp);
        comparePressure(
            'CSG', _wellDataForHour(hourIndex, row.well).csg, previousData.csg);

        if (_useGasAccumulator) {
          final currentGas = double.tryParse(
              _wellDataForHour(hourIndex, row.well).currentGasAccum.trim());
          final previousGas =
              double.tryParse(previousData.currentGasAccum.trim());
          if (currentGas != null &&
              previousGas != null &&
              (currentGas - previousGas).abs() > 500) {
            warnings
                .add('${row.well} gas accumulator changed by more than 500.');
          }
        }

        void compareGaugeList(
            String label,
            List<ProductionGaugeEntry> currentEntries,
            List<ProductionGaugeEntry> previousEntries) {
          final count = currentEntries.length < previousEntries.length
              ? currentEntries.length
              : previousEntries.length;
          for (var gaugeIndex = 0; gaugeIndex < count; gaugeIndex++) {
            final currentGauge = currentEntries[gaugeIndex].asInches();
            final previousGauge = previousEntries[gaugeIndex].asInches();
            if ((currentGauge - previousGauge).abs() > 24) {
              warnings.add(
                  '${row.well} $label ${gaugeIndex + 1} changed by more than 24 inches.');
            }
          }
        }

        final currentData = _wellDataForHour(hourIndex, row.well);
        compareGaugeList(
          'Water Tank',
          currentData.waterTankGaugeEntries,
          previousData.waterTankGaugeEntries,
        );
        compareGaugeList(
          'Oil Tank',
          currentData.oilTankGaugeEntries,
          previousData.oilTankGaugeEntries,
        );
      }
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
                  for (final warning in warnings.take(10))
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

    setState(() {
      _savingHour = true;
      _hourValidationMessage = null;
    });

    final updatedRows = List<ProductionReportRow>.from(_storedRows)
      ..removeWhere(
        (item) =>
            item.hourIndex == hourIndex && enteredWells.contains(item.well),
      )
      ..addAll(rows)
      ..sort((a, b) {
        final hourCompare = a.hourIndex.compareTo(b.hourIndex);
        if (hourCompare != 0) return hourCompare;
        final wellOrder = _activeWells;
        final ai = wellOrder.indexOf(a.well);
        final bi = wellOrder.indexOf(b.well);
        if (ai == -1 && bi == -1) return a.well.compareTo(b.well);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    _shift = _shift.copyWith(
      activeJobId: _activeJob?.id ?? _shift.activeJobId,
      hourlyChecks: _controllers.map((item) => item.toCheck()).toList(),
      savedRows: updatedRows,
      inventory: _shift.inventory.copyWith(productionRows: updatedRows),
      selectedTextHour: _shift.selectedTextHour ?? hourIndex,
    );
    await _service.saveActiveShift(_shift);

    for (final row in rows) {
      await _roundStorage.saveReading(
        RoundReading(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          roundLabel: row.time,
          oilRate: _fmt(row.oilProduction),
          waterRate: _fmt(row.waterProduction),
          gasRate: _fmt(_baseGasToDisplay(row.gas24HourRate)),
          tubingPressure: row.tbg,
          casingPressure: row.csg,
          differentialPressure: row.gasDifferential,
          gasTemp: row.gasTemp,
          choke: _formatChk(row.choke, row.chokeType),
          notes: row.notes,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _savingHour = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('${_controllers[hourIndex].time} Round saved successfully.'),
      ),
    );
  }

  ProductionWellCheckData? _latestSavedWellData(int hourIndex, String well) {
    for (var index = hourIndex - 1; index >= 0; index--) {
      if (!_isHourSaved(index)) continue;
      return _controllers[index].dataForWell(well, _chokeTypeForWell(well));
    }
    return null;
  }

  void _goToNextHour() {
    if (_activeHourIndex >= _controllers.length - 1) {
      return;
    }
    setState(() => _activeHourIndex += 1);
  }

  void _goToPreviousHour() {
    if (_activeHourIndex <= 0) {
      return;
    }
    setState(() => _activeHourIndex -= 1);
  }

  Widget _hourNavigationControls() {
    if (_controllers.isEmpty) {
      return const SizedBox.shrink();
    }

    final hourIndex = _activeHourIndex;
    final canGoPrevious = hourIndex > 0;
    final canGoNext = hourIndex < _controllers.length - 1;

    return _section('Hour Navigation', [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canGoPrevious ? _goToPreviousHour : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous Hour'),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _controllers[hourIndex].time,
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canGoNext ? _goToNextHour : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next Hour'),
            ),
          ),
        ],
      ),
    ]);
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

  Widget _calcLine(String label, double value, {String suffix = 'bbl'}) {
    final unavailable = value.isNaN;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            unavailable
                ? '--'
                : (suffix.isEmpty ? _fmt(value) : '${_fmt(value)} $suffix'),
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inventorySummary() {
    final header = _shift.header;
    final wells = _activeWells;
    final inventory = _shift.inventory;
    return _section('Shift Baseline', [
      Text(
        [header.company, header.pad]
                .where((item) => item.trim().isNotEmpty)
                .join(' • ')
                .isEmpty
            ? 'Save Production Inventory to set company, pad, wells, and starting tanks.'
            : [header.company, header.pad]
                .where((item) => item.trim().isNotEmpty)
                .join(' • '),
        style: const TextStyle(color: Colors.white70),
      ),
      if (header.date.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Date: ${header.date}',
            style: const TextStyle(color: Colors.white70)),
      ],
      const SizedBox(height: 8),
      Text(
        'Well Choke Types: ${wells.isEmpty ? '-' : wells.map((well) => '$well ${_chokeTypeForWell(well)}').join(' • ')}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 8),
      Text(
        'Gas Setup: ${_shift.inventory.gasUnit.toUpperCase()} • ${_useGasAccumulator ? 'Gas Accumulator' : 'Manual Sales Gas Rate'}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      Text(
        'Wells: ${wells.isEmpty ? '-' : wells.join(', ')}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      SwitchListTile.adaptive(
        value: _useStartingReadings,
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Use Starting Readings',
          style:
              TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'When off, first saved hour becomes the baseline.',
          style: TextStyle(color: Colors.white70),
        ),
        onChanged: _setUseStartingReadings,
      ),
      if (_useStartingReadings) ...[
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _shift.inventory.startingGasAccum,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Starting Gas Accum'),
          onChanged: _setStartingGasAccum,
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: _shift.inventory.waterTanks.isNotEmpty
              ? _shift.inventory.waterTanks.first.gauge
              : '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Starting Water Tank'),
          onChanged: _setStartingWaterTank,
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: _shift.inventory.oilTanks.isNotEmpty
              ? _shift.inventory.oilTanks.first.gauge
              : '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Starting Oil Tank'),
          onChanged: _setStartingOilTank,
        ),
      ],
      const SizedBox(height: 8),
      for (final tank in inventory.waterTanks)
        Text(
          '${tank.name}: ${tank.gaugeEntry.entryText()} (${tank.gaugeEntry.inchesText().isEmpty ? '0' : tank.gaugeEntry.inchesText()} in) @ ${tank.bblPerInch} BBL/in',
          style: const TextStyle(color: Colors.white70),
        ),
      if (inventory.waterTanks.isNotEmpty) const SizedBox(height: 8),
      for (final tank in inventory.oilTanks)
        Text(
          '${tank.name}: ${tank.gaugeEntry.entryText()} (${tank.gaugeEntry.inchesText().isEmpty ? '0' : tank.gaugeEntry.inchesText()} in) @ ${tank.bblPerInch} BBL/in',
          style: const TextStyle(color: Colors.white70),
        ),
      const SizedBox(height: 10),
      _calcLine(
        'Starting Water BBL',
        _useStartingReadings && _hasStartingWaterReading()
            ? _startingWaterBbl()
            : double.nan,
      ),
      _calcLine(
        'Starting Oil BBL',
        _useStartingReadings && _hasStartingOilReading()
            ? _startingOilBbl()
            : double.nan,
      ),
      _calcLine(
        'Starting Gas Accum',
        _useStartingReadings &&
                _shift.inventory.startingGasAccum.trim().isNotEmpty
            ? _startingGasAccum()
            : double.nan,
        suffix: '',
      ),
      _calcLine(
        'Water Hauled Before Round',
        _n(inventory.waterHauledBeforeRound),
      ),
      _calcLine(
        'Oil Hauled Before Round',
        _n(inventory.oilHauledBeforeRound),
      ),
      _calcLine(
        'Water Pumped Before Round',
        _n(inventory.waterPumpedBeforeRound),
      ),
      _calcLine(
        'Oil Pumped Before Round',
        _n(inventory.oilPumpedBeforeRound),
      ),
    ]);
  }

  Widget _activeJobBanner() {
    final activeJob = _activeJob;
    if (activeJob == null) {
      final summary = [_shift.header.company, _shift.header.pad]
          .where((item) => item.trim().isNotEmpty)
          .join(' • ');
      if (_shift.activeJobId.trim().isNotEmpty || summary.isNotEmpty) {
        return _section('Active Job', [
          Text(
            summary.isEmpty ? 'Active shift job linked' : summary,
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Using active shift job link.',
            style: TextStyle(color: Colors.white70),
          ),
        ]);
      }

      return _section('Active Job', const [
        Text(
          'No active job currently selected. Start a job in Job Setup to link all Production modules.',
          style: TextStyle(color: Colors.white70),
        ),
      ]);
    }

    return _section('Active Job', [
      Text(
        activeJob.company.trim().isEmpty
            ? 'No company entered'
            : activeJob.company,
        style: const TextStyle(
            color: Color(0xFFCDA56A), fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _jobChip('Pad', activeJob.padName),
          _jobChip(
            activeJob.isMultiWellJob ? 'Wells' : 'Well',
            activeJob.resolvedWellNames.isEmpty
                ? ''
                : activeJob.resolvedWellNames.join(', '),
          ),
          _jobChip('Shift', activeJob.shift),
        ],
      ),
    ]);
  }

  Widget _jobChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFCDA56A).withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: ${value.trim().isEmpty ? 'Not entered' : value.trim()}',
        style:
            const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _hourlyCard(int index) {
    final controller = _controllers[index];
    final wells = _activeWells;
    if (wells.isEmpty) {
      return _section('Active Hour', const [
        Text(
          'No active wells found. Save Production Inventory or start an Active Job first.',
          style: TextStyle(color: Colors.white70),
        ),
      ]);
    }
    return _section('Active Hour • ${controller.time}', [
      DropdownButtonFormField<String>(
        initialValue:
            wells.contains(controller.well) ? controller.well : wells.first,
        decoration: const InputDecoration(labelText: 'Well'),
        items: [
          for (final well in wells)
            DropdownMenuItem(value: well, child: Text(well)),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            controller.selectWell(value, _chokeTypeForWell(value));
          });
          _persistShift();
        },
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Choke Selector'),
        subtitle: Text(_quickRoundChokeSummary(controller)),
        trailing: FilledButton(
          onPressed: () => _pickHourlyChoke(controller),
          child: const Text('Select'),
        ),
      ),
      const SizedBox(height: 8),
      _field(
        'Hours Since Previous Reading',
        controller.hoursSincePrevious,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        helperText: 'Required after the first saved reading for this well.',
      ),
      _field('TBG', controller.tbg, suffix: 'PSI'),
      _field('ICP', controller.icp, suffix: 'PSI'),
      _field('CSG', controller.csg, suffix: 'PSI'),
      if (_useGasAccumulator)
        _field('Current Gas Accum', controller.currentGasAccum),
      if (!_useGasAccumulator)
        _field('Sales Gas Rate', controller.salesGasRate,
            suffix: _gasUnitLabel),
      _field('Gas Static', controller.gasStatic, suffix: 'PSI'),
      _field('Gas Differential', controller.gasDifferential, suffix: 'PSI'),
      _field('Gas Temperature', controller.gasTemp, suffix: '°'),
      _field('Water Specific Gravity', controller.waterSpecificGravity),
      _field('Wellhead Temperature', controller.wellheadTemp, suffix: '°'),
      _field('Water Temperature', controller.waterTemp, suffix: '°'),
      if (_showFlareSection)
        _field('Flare Rate', controller.flareRate, suffix: _gasUnitLabel),
      if (_showFlareSection)
        _field('Flare Pilot Temperature', controller.flarePilotTemp,
            suffix: '°'),
      if (_chemicalEnabled('Biocide'))
        _field('Biocide', controller.biocide, suffix: 'GPD'),
      if (_chemicalEnabled('Scavenger'))
        _field('Scavenger', controller.scavenger, suffix: 'GPD'),
      if (_chemicalEnabled('Defoamer'))
        _field('Defoamer', controller.defoamer, suffix: 'GPD'),
      if (_chemicalEnabled('Scale Inhibitor'))
        _field('Scale Inhibitor', controller.scaleInhibitor, suffix: 'GPD'),
      if (_showVruSection)
        _field('VRU Gas Rate', controller.vruGasRate, suffix: _gasUnitLabel),
      if (_showCompressorSection)
        _field(
          'Compressor Injection',
          controller.compressorInjection,
          suffix: _gasUnitLabel,
        ),
      if (_showVruSection) _field('VRU Suction', controller.vruSuction),
      if (_showVruSection) _field('VRU Discharge', controller.vruDischarge),
      _tankGaugeInputs(
        title: 'Current Water Tank Gauges',
        tanks: _shift.inventory.waterTanks,
        entries: controller.waterTankGaugeEntries,
      ),
      _tankGaugeInputs(
        title: 'Current Oil Tank Gauges',
        tanks: _shift.inventory.oilTanks,
        entries: controller.oilTankGaugeEntries,
      ),
      if (_showInventorySection)
        _field('Water Hauled This Hour', controller.waterHauled, suffix: 'BBL'),
      if (_showInventorySection)
        _field('Oil Hauled This Hour', controller.oilHauled, suffix: 'BBL'),
      if (_showInventorySection)
        _field('Water Pumped This Hour', controller.waterPumped, suffix: 'BBL'),
      if (_showInventorySection)
        _field('Oil Pumped This Hour', controller.oilPumped, suffix: 'BBL'),
      _field('Sand Rate', controller.sandRate),
      if (_showNotesSection)
        _field('Notes', controller.notes,
            keyboardType: TextInputType.text, lines: 3),
      _section('Calculated (Read Only)', [
        _calcLine('Current Water BBL', _currentWaterBbl(index)),
        _calcLine('Current Oil BBL', _currentOilBbl(index)),
        _calcLine('Hourly Water Production', _waterProduction(index)),
        _calcLine('Hourly Oil Production', _oilProduction(index)),
        _calcLine(
          _useGasAccumulator ? 'Hourly Gas' : 'Hourly Gas (Derived)',
          _baseGasToDisplay(_hourlyGas(index)),
          suffix: _gasUnitLabel,
        ),
        _calcLine(
          '24 Hour Gas Rate',
          _baseGasToDisplay(_gas24Hour(index)),
          suffix: _gasUnitLabel,
        ),
      ]),
      if (_showEcdSection) _oilCushionSection(index),
    ]);
  }

  ChokeSelection _selectionForController(_HourlyCheckControllers controller) {
    final raw = controller.choke.text.trim();
    final match = RegExp(r'(\d{1,2})').firstMatch(raw);
    final size = int.tryParse(match?.group(1) ?? '');
    if (size == null || size < 2 || size > 64 || raw.isEmpty) {
      return const ChokeSelection(type: ChokeTypes.none);
    }
    final type =
        controller.chokeType.trim().toUpperCase() == ChokeTypes.positive
            ? ChokeTypes.positive
            : ChokeTypes.adjustable;
    return ChokeSelection(type: type, size64: size);
  }

  String _quickRoundChokeSummary(_HourlyCheckControllers controller) {
    final selection = _selectionForController(controller);
    if (selection.isNone) return 'None / Clear';
    return formatChokeDisplay(selection);
  }

  Future<void> _pickHourlyChoke(_HourlyCheckControllers controller) async {
    final picked = await showChokeSelectorSheet(
      context,
      initial: _selectionForController(controller),
      allowNone: true,
    );
    if (!mounted || picked == null) return;

    setState(() {
      if (picked.isNone || picked.size64 == null) {
        controller.choke.clear();
        controller.chokeType = '';
        return;
      }
      controller.chokeType = picked.type == ChokeTypes.positive ? 'POS' : 'ADJ';
      controller.choke.text = '${picked.size64}/64"';
    });
    await _persistShift();
  }

  Widget _hourProgressSection() {
    final hourIndex = _activeHourIndex;
    return _section('Round Progress', [
      Text(
        'Current Hour: ${_controllers[hourIndex].time}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      for (final well in _activeWells)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                _isWellEntered(hourIndex, well)
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: _isWellEntered(hourIndex, well)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  well,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _hourActionButton() {
    if (_controllers.isEmpty) {
      return const SizedBox.shrink();
    }

    final hourIndex = _activeHourIndex;
    final time = _controllers[hourIndex].time;
    final hasNextHour = hourIndex < _controllers.length - 1;
    final hourSaved = _isHourSaved(hourIndex);

    if (hourSaved && hasNextHour) {
      final nextTime = _controllers[hourIndex + 1].time;
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _goToNextHour,
          icon: const Icon(Icons.arrow_forward),
          label: Text('Next Hour ($nextTime)'),
        ),
      );
    }

    if (hourSaved && !hasNextHour) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('All Hours Saved'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _savingHour ? null : _saveActiveHour,
        icon: _savingHour
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: Text(_savingHour ? 'Saving Round...' : 'Save $time Round'),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? suffix,
    String? helperText,
    TextInputType? keyboardType,
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboardType ??
            (lines > 1
                ? TextInputType.multiline
                : const TextInputType.numberWithOptions(decimal: true)),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          helperText: helperText,
          errorText: _invalidHourControllers.contains(controller)
              ? 'Cannot be negative'
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
        onChanged: (_) {
          setState(() {
            _invalidHourControllers.remove(controller);
            if (_invalidHourControllers.isEmpty) {
              _hourValidationMessage = null;
            }
          });
          _persistShift();
        },
      ),
    );
  }

  List<Widget> _gaugeInputs(_GaugeEntryControllers controller) {
    final gaugeMode = _shift.inventory.gaugeEntryType;
    if (gaugeMode == 'feetInches') {
      return [
        WwNumberField(
          label: 'Feet',
          controller: controller.feet,
          errorText: _invalidHourControllers.contains(controller.feet)
              ? 'Cannot be negative'
              : null,
          onChanged: (_) {
            setState(() {
              _invalidHourControllers.remove(controller.feet);
              if (_invalidHourControllers.isEmpty) {
                _hourValidationMessage = null;
              }
            });
            _persistShift();
          },
        ),
        WwNumberField(
          label: 'Inches',
          controller: controller.inchesPart,
          errorText: _invalidHourControllers.contains(controller.inchesPart)
              ? 'Cannot be negative'
              : null,
          onChanged: (_) {
            setState(() {
              _invalidHourControllers.remove(controller.inchesPart);
              if (_invalidHourControllers.isEmpty) {
                _hourValidationMessage = null;
              }
            });
            _persistShift();
          },
        ),
      ];
    }
    if (gaugeMode == 'decimalFeet') {
      return [
        WwNumberField(
          label: 'Decimal Feet',
          controller: controller.decimalFeet,
          errorText: _invalidHourControllers.contains(controller.decimalFeet)
              ? 'Cannot be negative'
              : null,
          onChanged: (_) {
            setState(() {
              _invalidHourControllers.remove(controller.decimalFeet);
              if (_invalidHourControllers.isEmpty) {
                _hourValidationMessage = null;
              }
            });
            _persistShift();
          },
        ),
      ];
    }
    return [
      WwNumberField(
        label: 'Current Gauge (in)',
        controller: controller.inches,
        errorText: _invalidHourControllers.contains(controller.inches)
            ? 'Cannot be negative'
            : null,
        onChanged: (_) {
          setState(() {
            _invalidHourControllers.remove(controller.inches);
            if (_invalidHourControllers.isEmpty) {
              _hourValidationMessage = null;
            }
          });
          _persistShift();
        },
      ),
    ];
  }

  Widget _hourValidationCard() {
    final message = _hourValidationMessage;
    if (message == null) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFF3A1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _tankGaugeInputs({
    required String title,
    required List<ProductionTank> tanks,
    required List<_GaugeEntryControllers> entries,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < entries.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tanks[i].name,
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gauge Entry Type: ${_shift.inventory.gaugeEntryType == 'feetInches' ? 'Feet + Inches' : _shift.inventory.gaugeEntryType == 'decimalFeet' ? 'Decimal Feet' : 'Inches'}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  ..._gaugeInputs(entries[i]),
                  Text(
                    'Entered: ${entries[i].entry(_shift.inventory.gaugeEntryType).entryText()}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Converted Gauge: ${entries[i].convertedInchesText(_shift.inventory.gaugeEntryType)} in',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Quick Round', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Quick Round', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _activeJobBanner(),
          _hourValidationCard(),
          _section('Round Setup', [
            DropdownButtonFormField<String>(
              initialValue: _shift.roundStartTime,
              decoration: const InputDecoration(labelText: 'Start Time'),
              items: _roundTimes
                  .map((time) =>
                      DropdownMenuItem(value: time, child: Text(time)))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _shift = _shift.copyWith(roundStartTime: value));
                _service.saveActiveShift(_shift);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _shift.checkCount,
              decoration:
                  const InputDecoration(labelText: 'Number of hourly checks'),
              items: [
                for (int i = 1; i <= 24; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _shift = _shift.copyWith(checkCount: value));
                _service.saveActiveShift(_shift);
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _buildRound,
                icon: const Icon(Icons.construction),
                label: const Text('Build Round'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _clearRoundWithConfirm,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Round'),
              ),
            ),
            _quickRoundReminderSetupCard(),
          ]),
          _inventorySummary(),
          if (_shift.hourlyChecks.isEmpty)
            _section('Hourly Checks', const [
              Text(
                'Build a round after saving Production Inventory. Quick Round is the only place hourly field data is entered.',
                style: TextStyle(color: Colors.white70),
              ),
            ]),
          if (_shift.hourlyChecks.isNotEmpty) ...[
            _hourNavigationControls(),
            _hourProgressSection(),
            _hourlyCard(_activeHourIndex),
            SizedBox(
              width: double.infinity,
              child: _hourActionButton(),
            ),
            if (_isHourSaved(_activeHourIndex)) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ShiftReportScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('View Production Report'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HourlyCheckControllers {
  _HourlyCheckControllers({
    required this.time,
    required this.well,
    required this.gaugeEntryType,
    required this.hoursSincePrevious,
    required this.choke,
    required this.chokeType,
    required this.tbg,
    required this.icp,
    required this.csg,
    required this.currentGasAccum,
    required this.salesGasRate,
    required this.gasStatic,
    required this.gasDifferential,
    required this.gasTemp,
    required this.waterSpecificGravity,
    required this.wellheadTemp,
    required this.waterTemp,
    required this.flareRate,
    required this.flarePilotTemp,
    required this.biocide,
    required this.scavenger,
    required this.defoamer,
    required this.scaleInhibitor,
    required this.vruGasRate,
    required this.compressorInjection,
    required this.vruSuction,
    required this.vruDischarge,
    required this.waterTankGaugeEntries,
    required this.oilTankGaugeEntries,
    required this.waterHauled,
    required this.oilHauled,
    required this.waterPumped,
    required this.oilPumped,
    required this.sandRate,
    required this.notes,
    required this.beginningOilInventory,
    required this.expectedOilInventory,
    required this.maximumCushion,
    required Map<String, ProductionWellCheckData> wellDataByName,
  }) : _wellDataByName = wellDataByName;

  factory _HourlyCheckControllers.fromCheck({
    required ProductionHourlyCheck check,
    required List<String> wells,
    required int waterTankCount,
    required int oilTankCount,
    required String gaugeEntryType,
    required String Function(String well) chokeTypeForWell,
  }) {
    ProductionWellCheckData normalizeData(ProductionWellCheckData data) {
      final water = List<String>.from(data.waterTankGauges);
      final oil = List<String>.from(data.oilTankGauges);
      final waterEntries = List<ProductionGaugeEntry>.from(
        data.waterTankGaugeEntries,
      );
      final oilEntries = List<ProductionGaugeEntry>.from(
        data.oilTankGaugeEntries,
      );

      while (water.length < waterTankCount) {
        water.add('');
      }
      while (oil.length < oilTankCount) {
        oil.add('');
      }
      while (waterEntries.length < waterTankCount) {
        final fallback = waterEntries.length < water.length
            ? water[waterEntries.length]
            : '';
        waterEntries.add(ProductionGaugeEntry.fromLegacyGauge(fallback));
      }
      while (oilEntries.length < oilTankCount) {
        final fallback =
            oilEntries.length < oil.length ? oil[oilEntries.length] : '';
        oilEntries.add(ProductionGaugeEntry.fromLegacyGauge(fallback));
      }
      if (water.length > waterTankCount) {
        water.removeRange(waterTankCount, water.length);
      }
      if (oil.length > oilTankCount) {
        oil.removeRange(oilTankCount, oil.length);
      }
      if (waterEntries.length > waterTankCount) {
        waterEntries.removeRange(waterTankCount, waterEntries.length);
      }
      if (oilEntries.length > oilTankCount) {
        oilEntries.removeRange(oilTankCount, oilEntries.length);
      }

      return ProductionWellCheckData(
        choke: data.choke,
        chokeType: data.chokeType,
        hoursSincePrevious: data.hoursSincePrevious,
        tbg: data.tbg,
        icp: data.icp,
        csg: data.csg,
        currentGasAccum: data.currentGasAccum,
        salesGasRate: data.salesGasRate,
        gasStatic: data.gasStatic,
        gasDifferential: data.gasDifferential,
        gasTemp: data.gasTemp,
        waterSpecificGravity: data.waterSpecificGravity,
        wellheadTemp: data.wellheadTemp,
        waterTemp: data.waterTemp,
        flareRate: data.flareRate,
        flarePilotTemp: data.flarePilotTemp,
        biocide: data.biocide,
        scavenger: data.scavenger,
        defoamer: data.defoamer,
        scaleInhibitor: data.scaleInhibitor,
        vruGasRate: data.vruGasRate,
        compressorInjection: data.compressorInjection,
        vruSuction: data.vruSuction,
        vruDischarge: data.vruDischarge,
        waterTankGauges: water,
        oilTankGauges: oil,
        waterTankGaugeEntries: waterEntries,
        oilTankGaugeEntries: oilEntries,
        waterHauled: data.waterHauled,
        oilHauled: data.oilHauled,
        waterPumped: data.waterPumped,
        oilPumped: data.oilPumped,
        sandRate: data.sandRate,
        notes: data.notes,
        beginningOilInventory: data.beginningOilInventory,
        expectedOilInventory: data.expectedOilInventory,
        maximumCushion: data.maximumCushion,
      );
    }

    final persistedMap = Map<String, ProductionWellCheckData>.from(
      check.wellChecks,
    );
    if (persistedMap.isEmpty) {
      final fallbackWell = check.well.trim().isEmpty ? wells.first : check.well;
      persistedMap[fallbackWell] =
          ProductionWellCheckData.fromHourlyCheck(check);
    }

    final wellDataByName = <String, ProductionWellCheckData>{
      for (final well in wells)
        well: normalizeData(
          persistedMap[well] ??
              ProductionWellCheckData(chokeType: chokeTypeForWell(well)),
        ),
    };

    final selectedWell = wells.contains(check.well) ? check.well : wells.first;
    final selectedData = wellDataByName[selectedWell]!;

    return _HourlyCheckControllers(
      time: check.time,
      well: selectedWell,
      gaugeEntryType: gaugeEntryType,
      hoursSincePrevious:
          TextEditingController(text: selectedData.hoursSincePrevious),
      choke: TextEditingController(text: selectedData.choke),
      chokeType: chokeTypeForWell(selectedWell),
      tbg: TextEditingController(text: selectedData.tbg),
      icp: TextEditingController(text: selectedData.icp),
      csg: TextEditingController(text: selectedData.csg),
      currentGasAccum:
          TextEditingController(text: selectedData.currentGasAccum),
      salesGasRate: TextEditingController(text: selectedData.salesGasRate),
      gasStatic: TextEditingController(text: selectedData.gasStatic),
      gasDifferential:
          TextEditingController(text: selectedData.gasDifferential),
      gasTemp: TextEditingController(text: selectedData.gasTemp),
      waterSpecificGravity:
          TextEditingController(text: selectedData.waterSpecificGravity),
      wellheadTemp: TextEditingController(text: selectedData.wellheadTemp),
      waterTemp: TextEditingController(text: selectedData.waterTemp),
      flareRate: TextEditingController(text: selectedData.flareRate),
      flarePilotTemp: TextEditingController(text: selectedData.flarePilotTemp),
      biocide: TextEditingController(text: selectedData.biocide),
      scavenger: TextEditingController(text: selectedData.scavenger),
      defoamer: TextEditingController(text: selectedData.defoamer),
      scaleInhibitor: TextEditingController(text: selectedData.scaleInhibitor),
      vruGasRate: TextEditingController(text: selectedData.vruGasRate),
      compressorInjection:
          TextEditingController(text: selectedData.compressorInjection),
      vruSuction: TextEditingController(text: selectedData.vruSuction),
      vruDischarge: TextEditingController(text: selectedData.vruDischarge),
      waterTankGaugeEntries: selectedData.waterTankGaugeEntries
          .map(_GaugeEntryControllers.fromEntry)
          .toList(),
      oilTankGaugeEntries: selectedData.oilTankGaugeEntries
          .map(_GaugeEntryControllers.fromEntry)
          .toList(),
      waterHauled: TextEditingController(text: selectedData.waterHauled),
      oilHauled: TextEditingController(text: selectedData.oilHauled),
      waterPumped: TextEditingController(text: selectedData.waterPumped),
      oilPumped: TextEditingController(text: selectedData.oilPumped),
      sandRate: TextEditingController(text: selectedData.sandRate),
      notes: TextEditingController(text: selectedData.notes),
      beginningOilInventory:
          TextEditingController(text: selectedData.beginningOilInventory),
      expectedOilInventory:
          TextEditingController(text: selectedData.expectedOilInventory),
      maximumCushion: TextEditingController(text: selectedData.maximumCushion),
      wellDataByName: wellDataByName,
    );
  }

  final String time;
  String well;
  final String gaugeEntryType;
  String chokeType;
  final TextEditingController hoursSincePrevious;
  final TextEditingController choke;
  final TextEditingController tbg;
  final TextEditingController icp;
  final TextEditingController csg;
  final TextEditingController currentGasAccum;
  final TextEditingController salesGasRate;
  final TextEditingController gasStatic;
  final TextEditingController gasDifferential;
  final TextEditingController gasTemp;
  final TextEditingController waterSpecificGravity;
  final TextEditingController wellheadTemp;
  final TextEditingController waterTemp;
  final TextEditingController flareRate;
  final TextEditingController flarePilotTemp;
  final TextEditingController biocide;
  final TextEditingController scavenger;
  final TextEditingController defoamer;
  final TextEditingController scaleInhibitor;
  final TextEditingController vruGasRate;
  final TextEditingController compressorInjection;
  final TextEditingController vruSuction;
  final TextEditingController vruDischarge;
  final List<_GaugeEntryControllers> waterTankGaugeEntries;
  final List<_GaugeEntryControllers> oilTankGaugeEntries;
  final TextEditingController waterHauled;
  final TextEditingController oilHauled;
  final TextEditingController waterPumped;
  final TextEditingController oilPumped;
  final TextEditingController sandRate;
  final TextEditingController notes;
  final TextEditingController beginningOilInventory;
  final TextEditingController expectedOilInventory;
  final TextEditingController maximumCushion;
  final Map<String, ProductionWellCheckData> _wellDataByName;

  ProductionWellCheckData _snapshotCurrentWellData() {
    final waterEntries = waterTankGaugeEntries
        .map((item) => item.entry(gaugeEntryType))
        .toList();
    final oilEntries =
        oilTankGaugeEntries.map((item) => item.entry(gaugeEntryType)).toList();
    return ProductionWellCheckData(
      hoursSincePrevious: hoursSincePrevious.text.trim(),
      choke: choke.text.trim(),
      chokeType: chokeType,
      tbg: tbg.text.trim(),
      icp: icp.text.trim(),
      csg: csg.text.trim(),
      currentGasAccum: currentGasAccum.text.trim(),
      salesGasRate: salesGasRate.text.trim(),
      gasStatic: gasStatic.text.trim(),
      gasDifferential: gasDifferential.text.trim(),
      gasTemp: gasTemp.text.trim(),
      waterSpecificGravity: waterSpecificGravity.text.trim(),
      wellheadTemp: wellheadTemp.text.trim(),
      waterTemp: waterTemp.text.trim(),
      flareRate: flareRate.text.trim(),
      flarePilotTemp: flarePilotTemp.text.trim(),
      biocide: biocide.text.trim(),
      scavenger: scavenger.text.trim(),
      defoamer: defoamer.text.trim(),
      scaleInhibitor: scaleInhibitor.text.trim(),
      vruGasRate: vruGasRate.text.trim(),
      compressorInjection: compressorInjection.text.trim(),
      vruSuction: vruSuction.text.trim(),
      vruDischarge: vruDischarge.text.trim(),
      waterTankGauges: waterEntries.map((item) => item.inchesText()).toList(),
      oilTankGauges: oilEntries.map((item) => item.inchesText()).toList(),
      waterTankGaugeEntries: waterEntries,
      oilTankGaugeEntries: oilEntries,
      waterHauled: waterHauled.text.trim(),
      oilHauled: oilHauled.text.trim(),
      waterPumped: waterPumped.text.trim(),
      oilPumped: oilPumped.text.trim(),
      sandRate: sandRate.text.trim(),
      notes: notes.text.trim(),
      beginningOilInventory: beginningOilInventory.text.trim(),
      expectedOilInventory: expectedOilInventory.text.trim(),
      maximumCushion: maximumCushion.text.trim(),
    );
  }

  void _loadWellData(ProductionWellCheckData data, String nextChokeType) {
    hoursSincePrevious.text = data.hoursSincePrevious;
    choke.text = data.choke;
    chokeType = nextChokeType;
    tbg.text = data.tbg;
    icp.text = data.icp;
    csg.text = data.csg;
    currentGasAccum.text = data.currentGasAccum;
    salesGasRate.text = data.salesGasRate;
    gasStatic.text = data.gasStatic;
    gasDifferential.text = data.gasDifferential;
    gasTemp.text = data.gasTemp;
    waterSpecificGravity.text = data.waterSpecificGravity;
    wellheadTemp.text = data.wellheadTemp;
    waterTemp.text = data.waterTemp;
    flareRate.text = data.flareRate;
    flarePilotTemp.text = data.flarePilotTemp;
    biocide.text = data.biocide;
    scavenger.text = data.scavenger;
    defoamer.text = data.defoamer;
    scaleInhibitor.text = data.scaleInhibitor;
    vruGasRate.text = data.vruGasRate;
    compressorInjection.text = data.compressorInjection;
    vruSuction.text = data.vruSuction;
    vruDischarge.text = data.vruDischarge;
    waterHauled.text = data.waterHauled;
    oilHauled.text = data.oilHauled;
    waterPumped.text = data.waterPumped;
    oilPumped.text = data.oilPumped;
    sandRate.text = data.sandRate;
    notes.text = data.notes;
    beginningOilInventory.text = data.beginningOilInventory;
    expectedOilInventory.text = data.expectedOilInventory;
    maximumCushion.text = data.maximumCushion;

    for (var i = 0; i < waterTankGaugeEntries.length; i++) {
      final entry = i < data.waterTankGaugeEntries.length
          ? data.waterTankGaugeEntries[i]
          : const ProductionGaugeEntry();
      waterTankGaugeEntries[i].inches.text = entry.inches;
      waterTankGaugeEntries[i].feet.text = entry.feet;
      waterTankGaugeEntries[i].inchesPart.text = entry.inchesPart;
      waterTankGaugeEntries[i].decimalFeet.text = entry.decimalFeet;
    }

    for (var i = 0; i < oilTankGaugeEntries.length; i++) {
      final entry = i < data.oilTankGaugeEntries.length
          ? data.oilTankGaugeEntries[i]
          : const ProductionGaugeEntry();
      oilTankGaugeEntries[i].inches.text = entry.inches;
      oilTankGaugeEntries[i].feet.text = entry.feet;
      oilTankGaugeEntries[i].inchesPart.text = entry.inchesPart;
      oilTankGaugeEntries[i].decimalFeet.text = entry.decimalFeet;
    }
  }

  void selectWell(String nextWell, String nextChokeType) {
    _wellDataByName[well] = _snapshotCurrentWellData();
    final nextData = _wellDataByName[nextWell] ??
        ProductionWellCheckData(chokeType: nextChokeType);
    well = nextWell;
    _loadWellData(nextData, nextChokeType);
  }

  ProductionWellCheckData dataForWell(String targetWell, String chokeType) {
    _wellDataByName[well] = _snapshotCurrentWellData();
    return _wellDataByName[targetWell] ??
        ProductionWellCheckData(chokeType: chokeType);
  }

  ProductionHourlyCheck toCheck() {
    _wellDataByName[well] = _snapshotCurrentWellData();
    final current = _wellDataByName[well] ?? const ProductionWellCheckData();
    return ProductionHourlyCheck(
      time: time,
      well: well,
      wellChecks: Map<String, ProductionWellCheckData>.from(_wellDataByName),
      hoursSincePrevious: current.hoursSincePrevious,
      choke: current.choke,
      chokeType: current.chokeType,
      tbg: current.tbg,
      icp: current.icp,
      csg: current.csg,
      currentGasAccum: current.currentGasAccum,
      salesGasRate: current.salesGasRate,
      gasStatic: current.gasStatic,
      gasDifferential: current.gasDifferential,
      gasTemp: current.gasTemp,
      waterSpecificGravity: current.waterSpecificGravity,
      wellheadTemp: current.wellheadTemp,
      waterTemp: current.waterTemp,
      flareRate: current.flareRate,
      flarePilotTemp: current.flarePilotTemp,
      biocide: current.biocide,
      scavenger: current.scavenger,
      defoamer: current.defoamer,
      scaleInhibitor: current.scaleInhibitor,
      vruGasRate: current.vruGasRate,
      compressorInjection: current.compressorInjection,
      vruSuction: current.vruSuction,
      vruDischarge: current.vruDischarge,
      waterTankGauges: current.waterTankGauges,
      oilTankGauges: current.oilTankGauges,
      waterTankGaugeEntries: current.waterTankGaugeEntries,
      oilTankGaugeEntries: current.oilTankGaugeEntries,
      waterHauled: current.waterHauled,
      oilHauled: current.oilHauled,
      waterPumped: current.waterPumped,
      oilPumped: current.oilPumped,
      sandRate: current.sandRate,
      notes: current.notes,
    );
  }

  void dispose() {
    for (final controller in [
      hoursSincePrevious,
      choke,
      tbg,
      icp,
      csg,
      currentGasAccum,
      salesGasRate,
      gasStatic,
      gasDifferential,
      gasTemp,
      waterSpecificGravity,
      wellheadTemp,
      waterTemp,
      flareRate,
      flarePilotTemp,
      biocide,
      scavenger,
      defoamer,
      scaleInhibitor,
      vruGasRate,
      compressorInjection,
      vruSuction,
      vruDischarge,
      waterHauled,
      oilHauled,
      waterPumped,
      oilPumped,
      sandRate,
      notes,
      beginningOilInventory,
      expectedOilInventory,
      maximumCushion,
      ...waterTankGaugeEntries.expand((item) => item.controllers),
      ...oilTankGaugeEntries.expand((item) => item.controllers),
    ]) {
      controller.dispose();
    }
  }
}

class _GaugeEntryControllers {
  _GaugeEntryControllers({
    required this.inches,
    required this.feet,
    required this.inchesPart,
    required this.decimalFeet,
  });

  factory _GaugeEntryControllers.fromEntry(ProductionGaugeEntry entry) {
    return _GaugeEntryControllers(
      inches: TextEditingController(text: entry.inches),
      feet: TextEditingController(text: entry.feet),
      inchesPart: TextEditingController(text: entry.inchesPart),
      decimalFeet: TextEditingController(text: entry.decimalFeet),
    );
  }

  final TextEditingController inches;
  final TextEditingController feet;
  final TextEditingController inchesPart;
  final TextEditingController decimalFeet;

  ProductionGaugeEntry entry(String mode) => ProductionGaugeEntry(
        mode: mode,
        inches: inches.text.trim(),
        feet: feet.text.trim(),
        inchesPart: inchesPart.text.trim(),
        decimalFeet: decimalFeet.text.trim(),
      );

  String convertedInchesText(String mode) {
    final value = entry(mode).asInches();
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  List<TextEditingController> get controllers => [
        inches,
        feet,
        inchesPart,
        decimalFeet,
      ];
}
