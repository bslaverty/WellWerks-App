import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../models/round_reading.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../services/round_storage_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class PressureEntryScreen extends StatefulWidget {
  const PressureEntryScreen({super.key});

  @override
  State<PressureEntryScreen> createState() => _PressureEntryScreenState();
}

class _PressureEntryScreenState extends State<PressureEntryScreen> {
  static const _legacyInventoryKey = 'wellwerks_quick_round_start_inventory_v1';

  final _service = ProductionShiftService();
  final _jobStorage = JobStorageService();
  final _roundStorage = RoundStorageService();
  final _recoveryState = RecoveryStateService();
  bool _loading = true;
  int _activeHourIndex = 0;

  late ProductionShift _shift;
  JobSetup? _activeJob;
  final List<_HourlyCheckControllers> _controllers = [];

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
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    var shift = await _service.loadActiveShift();
    shift = await _migrateLegacyInventory(shift);
    final activeJob = await _jobStorage.loadActiveJob();
    if (activeJob != null && shift.activeJobId != activeJob.id) {
      shift = shift.copyWith(activeJobId: activeJob.id);
      await _service.saveActiveShift(shift);
    }
    _shift = shift;
    _activeJob = activeJob;
    _rebuildControllers();
    if (!mounted) return;
    setState(() {
      _activeHourIndex = _firstIncompleteHourIndex();
      _loading = false;
    });
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
      header: shift.header.wells.isEmpty
          ? shift.header.copyWith(wells: const ['Well 1'])
          : shift.header,
    );
    await _service.saveActiveShift(migrated);
    return migrated;
  }

  void _rebuildControllers() {
    final wells =
        _shift.header.wells.isEmpty ? const ['Well 1'] : _shift.header.wells;
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
    final wells =
        _shift.header.wells.isEmpty ? const ['Well 1'] : _shift.header.wells;
    final normalizedWell =
        wells.contains(check.well) ? check.well : wells.first;
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

  List<String> get _activeWells =>
      _shift.header.wells.isEmpty ? const ['Well 1'] : _shift.header.wells;

  bool _gaugeEntryHasValue(ProductionGaugeEntry entry) {
    return entry.inches.trim().isNotEmpty ||
        entry.feet.trim().isNotEmpty ||
        entry.inchesPart.trim().isNotEmpty ||
        entry.decimalFeet.trim().isNotEmpty;
  }

  ProductionWellCheckData _wellDataForHour(int hourIndex, String well) {
    return _controllers[hourIndex].dataForWell(well, _chokeTypeForWell(well));
  }

  bool _isWellComplete(int hourIndex, String well) {
    final data = _wellDataForHour(hourIndex, well);
    final hasGas = _useGasAccumulator
        ? data.currentGasAccum.trim().isNotEmpty
        : data.salesGasRate.trim().isNotEmpty;
    final hasWaterGauges =
        data.waterTankGaugeEntries.every(_gaugeEntryHasValue);
    final hasOilGauges = data.oilTankGaugeEntries.every(_gaugeEntryHasValue);
    return data.choke.trim().isNotEmpty &&
        data.tbg.trim().isNotEmpty &&
        data.csg.trim().isNotEmpty &&
        hasGas &&
        hasWaterGauges &&
        hasOilGauges;
  }

  bool _isHourSaved(int hourIndex) {
    return _activeWells.every(
      (well) => _shift.savedRows.any(
        (row) => row.hourIndex == hourIndex && row.well == well,
      ),
    );
  }

  String? _validationMessageForWell(int hourIndex, String well) {
    final data = _wellDataForHour(hourIndex, well);
    if (data.choke.trim().isEmpty) return '$well is missing Choke Value.';
    if (data.tbg.trim().isEmpty) return '$well is missing TBG.';
    if (data.csg.trim().isEmpty) return '$well is missing CSG.';
    if (_useGasAccumulator && data.currentGasAccum.trim().isEmpty) {
      return '$well is missing Current Gas Accum.';
    }
    if (!_useGasAccumulator && data.salesGasRate.trim().isEmpty) {
      return '$well is missing Sales Gas Rate.';
    }
    if (data.waterTankGaugeEntries
        .any((entry) => !_gaugeEntryHasValue(entry))) {
      return '$well is missing one or more water tank gauges.';
    }
    if (data.oilTankGaugeEntries.any((entry) => !_gaugeEntryHasValue(entry))) {
      return '$well is missing one or more oil tank gauges.';
    }
    return null;
  }

  Future<void> _refreshActiveJobReference() async {
    final activeJob = await _jobStorage.loadActiveJob();
    _activeJob = activeJob;
    final activeJobId = activeJob?.id ?? '';
    if (_shift.activeJobId == activeJobId) {
      return;
    }
    _shift = _shift.copyWith(activeJobId: activeJobId);
  }

  double _n(String value) => ProductionMath.parse(value);

  bool get _useGasAccumulator =>
      _shift.inventory.gasCalculationMethod == 'accumulator';

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
      activeJobId: _activeJob?.id ?? '',
      hourlyChecks: _buildBlankChecks(),
      savedRows: const [],
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
      activeJobId: _activeJob?.id ?? '',
      hourlyChecks: const [],
      savedRows: const [],
      clearSelectedTextHour: true,
    );
    _rebuildControllers();
    await _service.saveActiveShift(_shift);
    if (!mounted) return;
    setState(() => _activeHourIndex = 0);
  }

  ProductionReportRow? _latestSavedBefore(int index, String well) {
    final previous = _shift.savedRows
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
    if (previous == null) return _startingWaterBbl();
    return previous.currentWaterBbl;
  }

  double _previousOilBbl(int index) {
    final previous = _latestSavedBefore(index, _controllers[index].well);
    if (previous == null) return _startingOilBbl();
    return previous.currentOilBbl;
  }

  double _previousGasAccum(int index) {
    final previous = _latestSavedBefore(index, _controllers[index].well);
    if (previous == null) return _startingGasAccum();
    return previous.currentGasAccum;
  }

  double _hourlyGas(int index) {
    if (!_useGasAccumulator) {
      final gasRate = _displayGasToBase(_controllers[index].salesGasRate.text);
      return gasRate / 24;
    }
    return ProductionMath.hourlyGas(
      currentGasAccum: _n(_controllers[index].currentGasAccum.text),
      previousGasAccum: _previousGasAccum(index),
    );
  }

  double _gas24Hour(int index) {
    if (!_useGasAccumulator) {
      return _displayGasToBase(_controllers[index].salesGasRate.text);
    }
    return ProductionMath.gas24Hour(_hourlyGas(index));
  }

  double _waterProduction(int index) {
    final check = _controllers[index];
    return ProductionMath.waterProduction(
      currentWaterBbl: _currentWaterBbl(index),
      previousWaterBbl: _previousWaterBbl(index),
      waterHauled: _n(check.waterHauled.text),
      waterPumped: _n(check.waterPumped.text),
      preRoundWaterHauled: _n(_shift.inventory.waterHauledBeforeRound),
      preRoundWaterPumped: _n(_shift.inventory.waterPumpedBeforeRound),
      isFirstHour: index == 0,
    );
  }

  double _oilProduction(int index) {
    final check = _controllers[index];
    return ProductionMath.oilProduction(
      currentOilBbl: _currentOilBbl(index),
      previousOilBbl: _previousOilBbl(index),
      oilHauled: _n(check.oilHauled.text),
      oilPumped: _n(check.oilPumped.text),
      preRoundOilHauled: _n(_shift.inventory.oilHauledBeforeRound),
      preRoundOilPumped: _n(_shift.inventory.oilPumpedBeforeRound),
      isFirstHour: index == 0,
    );
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
    return ProductionMath.totalTankBbl(
      _shift.inventory.waterTanks,
      data.waterTankGaugeEntries
          .map((item) => item.asInches().toString())
          .toList(),
    );
  }

  double _currentOilBblForData(ProductionWellCheckData data) {
    return ProductionMath.totalTankBbl(
      _shift.inventory.oilTanks,
      data.oilTankGaugeEntries
          .map((item) => item.asInches().toString())
          .toList(),
    );
  }

  double _hourlyGasForData(
      int index, ProductionWellCheckData data, String well) {
    if (!_useGasAccumulator) {
      final gasRate = _displayGasToBase(data.salesGasRate);
      return gasRate / 24;
    }
    return ProductionMath.hourlyGas(
      currentGasAccum: _n(data.currentGasAccum),
      previousGasAccum: _latestSavedBefore(index, well)?.currentGasAccum ??
          _startingGasAccum(),
    );
  }

  double _gas24HourForData(
      int index, ProductionWellCheckData data, String well) {
    if (!_useGasAccumulator) {
      return _displayGasToBase(data.salesGasRate);
    }
    return ProductionMath.gas24Hour(_hourlyGasForData(index, data, well));
  }

  double _waterProductionForData(
      int index, ProductionWellCheckData data, String well) {
    return ProductionMath.waterProduction(
      currentWaterBbl: _currentWaterBblForData(data),
      previousWaterBbl: _latestSavedBefore(index, well)?.currentWaterBbl ??
          _startingWaterBbl(),
      waterHauled: _n(data.waterHauled),
      waterPumped: _n(data.waterPumped),
      preRoundWaterHauled: _n(_shift.inventory.waterHauledBeforeRound),
      preRoundWaterPumped: _n(_shift.inventory.waterPumpedBeforeRound),
      isFirstHour: index == 0,
    );
  }

  double _oilProductionForData(
      int index, ProductionWellCheckData data, String well) {
    return ProductionMath.oilProduction(
      currentOilBbl: _currentOilBblForData(data),
      previousOilBbl:
          _latestSavedBefore(index, well)?.currentOilBbl ?? _startingOilBbl(),
      oilHauled: _n(data.oilHauled),
      oilPumped: _n(data.oilPumped),
      preRoundOilHauled: _n(_shift.inventory.oilHauledBeforeRound),
      preRoundOilPumped: _n(_shift.inventory.oilPumpedBeforeRound),
      isFirstHour: index == 0,
    );
  }

  ProductionReportRow _buildRowForWell(
    int hourIndex,
    String well,
    ProductionWellCheckData data,
  ) {
    return ProductionReportRow(
      hourIndex: hourIndex,
      time: _controllers[hourIndex].time,
      well: well,
      choke: data.choke.trim(),
      chokeType: _chokeTypeForWell(well),
      tbg: data.tbg.trim(),
      icp: data.icp.trim(),
      csg: data.csg.trim(),
      waterProduction: _waterProductionForData(hourIndex, data, well),
      oilProduction: _oilProductionForData(hourIndex, data, well),
      hourlyGas: _hourlyGasForData(hourIndex, data, well),
      gas24HourRate: _gas24HourForData(hourIndex, data, well),
      salesGasRate: _gas24HourForData(hourIndex, data, well),
      gasStatic: data.gasStatic.trim(),
      gasDifferential: data.gasDifferential.trim(),
      gasTemp: data.gasTemp.trim(),
      waterSpecificGravity: data.waterSpecificGravity.trim(),
      wellheadTemp: data.wellheadTemp.trim(),
      waterTemp: data.waterTemp.trim(),
      flareRate: _storeGasField(data.flareRate),
      flarePilotTemp: data.flarePilotTemp.trim(),
      biocide: data.biocide.trim(),
      vruGasRate: _storeGasField(data.vruGasRate),
      compressorInjection: _storeGasField(data.compressorInjection),
      vruSuction: data.vruSuction.trim(),
      vruDischarge: data.vruDischarge.trim(),
      sandRate: data.sandRate.trim(),
      waterGaugeText:
          _gaugeText(_shift.inventory.waterTanks, data.waterTankGaugeEntries),
      oilGaugeText:
          _gaugeText(_shift.inventory.oilTanks, data.oilTankGaugeEntries),
      currentWaterBbl: _currentWaterBblForData(data),
      currentOilBbl: _currentOilBblForData(data),
      currentGasAccum: _useGasAccumulator
          ? _n(data.currentGasAccum)
          : (_latestSavedBefore(hourIndex, well)?.currentGasAccum ??
              _startingGasAccum()),
      waterHauled: _n(data.waterHauled),
      oilHauled: _n(data.oilHauled),
      waterPumped: _n(data.waterPumped),
      oilPumped: _n(data.oilPumped),
      notes: data.notes.trim(),
    );
  }

  Future<void> _saveActiveHour() async {
    final hourIndex = _activeHourIndex;
    for (final well in _activeWells) {
      final message = _validationMessageForWell(hourIndex, well);
      if (message != null) {
        setState(() {
          _controllers[hourIndex].selectWell(well, _chokeTypeForWell(well));
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        return;
      }
    }

    await _persistShift();
    final rows = <ProductionReportRow>[
      for (final well in _activeWells)
        _buildRowForWell(hourIndex, well, _wellDataForHour(hourIndex, well)),
    ];

    final updatedRows = List<ProductionReportRow>.from(_shift.savedRows)
      ..removeWhere((item) => item.hourIndex == hourIndex)
      ..addAll(rows)
      ..sort((a, b) {
        final hourCompare = a.hourIndex.compareTo(b.hourIndex);
        if (hourCompare != 0) return hourCompare;
        return a.well.compareTo(b.well);
      });

    _shift = _shift.copyWith(
      activeJobId: _activeJob?.id ?? '',
      hourlyChecks: _controllers.map((item) => item.toCheck()).toList(),
      savedRows: updatedRows,
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
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_controllers[hourIndex].time} Round Saved ✓')),
    );
  }

  void _goToNextHour() {
    if (_activeHourIndex >= _controllers.length - 1) {
      return;
    }
    setState(() => _activeHourIndex += 1);
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
            suffix.isEmpty ? _fmt(value) : '${_fmt(value)} $suffix',
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
        'Well Choke Types: ${(header.wells.isEmpty ? const [
            'Well 1'
          ] : header.wells).map((well) => '$well ${_chokeTypeForWell(well)}').join(' • ')}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 8),
      Text(
        'Gas Setup: ${_shift.inventory.gasUnit.toUpperCase()} • ${_useGasAccumulator ? 'Gas Accumulator' : 'Manual Sales Gas Rate'}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      Text(
        'Wells: ${(header.wells.isEmpty ? const [
            'Well 1'
          ] : header.wells).join(', ')}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
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
      _calcLine('Starting Water BBL', _startingWaterBbl()),
      _calcLine('Starting Oil BBL', _startingOilBbl()),
      _calcLine('Starting Gas Accum', _startingGasAccum(), suffix: ''),
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
      return _section('Active Job', const [
        Text(
          'No active job found. Start a job first to link Quick Round entries, but Quick Round will still work as it does today.',
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
          _jobChip('Well', activeJob.primaryWell),
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
    final wells =
        _shift.header.wells.isEmpty ? const ['Well 1'] : _shift.header.wells;
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
      Text(
        'Choke Type: ${controller.chokeType}',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 8),
      _field(
        'Choke Value',
        controller.choke,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      _field('Flare Rate', controller.flareRate, suffix: _gasUnitLabel),
      _field('Flare Pilot Temperature', controller.flarePilotTemp, suffix: '°'),
      _field('Biocide', controller.biocide, suffix: 'GPD'),
      _field('VRU Gas Rate', controller.vruGasRate, suffix: _gasUnitLabel),
      _field(
        'Compressor Injection',
        controller.compressorInjection,
        suffix: _gasUnitLabel,
      ),
      _field('VRU Suction', controller.vruSuction),
      _field('VRU Discharge', controller.vruDischarge),
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
      _field('Water Hauled This Hour', controller.waterHauled, suffix: 'BBL'),
      _field('Oil Hauled This Hour', controller.oilHauled, suffix: 'BBL'),
      _field('Water Pumped This Hour', controller.waterPumped, suffix: 'BBL'),
      _field('Oil Pumped This Hour', controller.oilPumped, suffix: 'BBL'),
      _field('Sand Rate', controller.sandRate),
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
    ]);
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
                _isWellComplete(hourIndex, well)
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: _isWellComplete(hourIndex, well)
                    ? Colors.green
                    : Colors.white54,
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
        onPressed: _saveActiveHour,
        icon: const Icon(Icons.save),
        label: Text('Save $time Round'),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? suffix,
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
        onChanged: (_) {
          setState(() {});
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
          onChanged: (_) {
            setState(() {});
            _persistShift();
          },
        ),
        WwNumberField(
          label: 'Inches',
          controller: controller.inchesPart,
          onChanged: (_) {
            setState(() {});
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
          onChanged: (_) {
            setState(() {});
            _persistShift();
          },
        ),
      ];
    }
    return [
      WwNumberField(
        label: 'Current Gauge (in)',
        controller: controller.inches,
        onChanged: (_) {
          setState(() {});
          _persistShift();
        },
      ),
    ];
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
            _hourProgressSection(),
            _hourlyCard(_activeHourIndex),
            SizedBox(
              width: double.infinity,
              child: _hourActionButton(),
            ),
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
      wellDataByName: wellDataByName,
    );
  }

  final String time;
  String well;
  final String gaugeEntryType;
  String chokeType;
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
  final Map<String, ProductionWellCheckData> _wellDataByName;

  ProductionWellCheckData _snapshotCurrentWellData() {
    final waterEntries = waterTankGaugeEntries
        .map((item) => item.entry(gaugeEntryType))
        .toList();
    final oilEntries =
        oilTankGaugeEntries.map((item) => item.entry(gaugeEntryType)).toList();
    return ProductionWellCheckData(
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
    );
  }

  void _loadWellData(ProductionWellCheckData data, String nextChokeType) {
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
