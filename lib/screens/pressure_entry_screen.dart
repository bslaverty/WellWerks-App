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
    setState(() => _loading = false);
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
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers
      ..clear()
      ..addAll(_shift.hourlyChecks.map(
        (check) => _HourlyCheckControllers.fromCheck(
          check: _normalizeCheck(check),
          waterTankCount: _shift.inventory.waterTanks.length,
          oilTankCount: _shift.inventory.oilTanks.length,
          gaugeEntryType: _shift.inventory.gaugeEntryType,
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
    final wells =
        _shift.header.wells.isEmpty ? const ['Well 1'] : _shift.header.wells;
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
    setState(() {});
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
    setState(() {});
  }

  ProductionReportRow? _latestSavedBefore(int index) {
    return ProductionMath.previousSavedRow(_shift.savedRows, index);
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
    final previous = _latestSavedBefore(index);
    if (previous == null) return _startingWaterBbl();
    return previous.currentWaterBbl;
  }

  double _previousOilBbl(int index) {
    final previous = _latestSavedBefore(index);
    if (previous == null) return _startingOilBbl();
    return previous.currentOilBbl;
  }

  double _previousGasAccum(int index) {
    final previous = _latestSavedBefore(index);
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
    List<_GaugeEntryControllers> gauges,
  ) {
    final parts = <String>[];
    for (var i = 0; i < tanks.length; i++) {
      final entry = gauges[i].entry(_shift.inventory.gaugeEntryType);
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

  Future<void> _saveHour(int index) async {
    await _persistShift();
    final controller = _controllers[index];
    final row = ProductionReportRow(
      hourIndex: index,
      time: controller.time,
      well: controller.well,
      choke: controller.choke.text.trim(),
      chokeType: _chokeTypeForWell(controller.well),
      tbg: controller.tbg.text.trim(),
      icp: controller.icp.text.trim(),
      csg: controller.csg.text.trim(),
      waterProduction: _waterProduction(index),
      oilProduction: _oilProduction(index),
      hourlyGas: _hourlyGas(index),
      gas24HourRate: _gas24Hour(index),
      salesGasRate: _gas24Hour(index),
      gasStatic: controller.gasStatic.text.trim(),
      gasDifferential: controller.gasDifferential.text.trim(),
      gasTemp: controller.gasTemp.text.trim(),
      waterSpecificGravity: controller.waterSpecificGravity.text.trim(),
      wellheadTemp: controller.wellheadTemp.text.trim(),
      waterTemp: controller.waterTemp.text.trim(),
      flareRate: _storeGasField(controller.flareRate.text),
      flarePilotTemp: controller.flarePilotTemp.text.trim(),
      biocide: controller.biocide.text.trim(),
      vruGasRate: _storeGasField(controller.vruGasRate.text),
      compressorInjection: _storeGasField(controller.compressorInjection.text),
      vruSuction: controller.vruSuction.text.trim(),
      vruDischarge: controller.vruDischarge.text.trim(),
      sandRate: controller.sandRate.text.trim(),
      waterGaugeText: _gaugeText(
          _shift.inventory.waterTanks, controller.waterTankGaugeEntries),
      oilGaugeText:
          _gaugeText(_shift.inventory.oilTanks, controller.oilTankGaugeEntries),
      currentWaterBbl: _currentWaterBbl(index),
      currentOilBbl: _currentOilBbl(index),
      currentGasAccum: _useGasAccumulator
          ? _n(controller.currentGasAccum.text)
          : _previousGasAccum(index),
      waterHauled: _n(controller.waterHauled.text),
      oilHauled: _n(controller.oilHauled.text),
      waterPumped: _n(controller.waterPumped.text),
      oilPumped: _n(controller.oilPumped.text),
      notes: controller.notes.text.trim(),
    );

    final updatedRows = List<ProductionReportRow>.from(_shift.savedRows)
      ..removeWhere((item) => item.hourIndex == index)
      ..add(row)
      ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));

    _shift = _shift.copyWith(
      activeJobId: _activeJob?.id ?? '',
      hourlyChecks: _controllers.map((item) => item.toCheck()).toList(),
      savedRows: updatedRows,
      selectedTextHour: _shift.selectedTextHour ?? index,
    );
    await _service.saveActiveShift(_shift);

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

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${row.time} saved to Production Report.')),
    );
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
    return _section('Hourly Check ${index + 1} • ${controller.time}', [
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
            controller.well = value;
            controller.chokeType = _chokeTypeForWell(value);
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
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _saveHour(index),
          icon: const Icon(Icons.save),
          label: Text('Save Hour (${controller.time})'),
        ),
      ),
    ]);
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
          for (int i = 0; i < _controllers.length; i++) _hourlyCard(i),
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
  });

  factory _HourlyCheckControllers.fromCheck({
    required ProductionHourlyCheck check,
    required int waterTankCount,
    required int oilTankCount,
    required String gaugeEntryType,
  }) {
    final water = List<String>.from(check.waterTankGauges);
    final oil = List<String>.from(check.oilTankGauges);
    final waterEntries = List<ProductionGaugeEntry>.from(
      check.waterTankGaugeEntries,
    );
    final oilEntries = List<ProductionGaugeEntry>.from(
      check.oilTankGaugeEntries,
    );
    while (water.length < waterTankCount) {
      water.add('');
    }
    while (oil.length < oilTankCount) {
      oil.add('');
    }
    while (waterEntries.length < waterTankCount) {
      final fallback =
          waterEntries.length < water.length ? water[waterEntries.length] : '';
      waterEntries.add(ProductionGaugeEntry.fromLegacyGauge(fallback));
    }
    while (oilEntries.length < oilTankCount) {
      final fallback =
          oilEntries.length < oil.length ? oil[oilEntries.length] : '';
      oilEntries.add(ProductionGaugeEntry.fromLegacyGauge(fallback));
    }
    return _HourlyCheckControllers(
      time: check.time,
      well: check.well,
      gaugeEntryType: gaugeEntryType,
      choke: TextEditingController(text: check.choke),
      chokeType: check.chokeType,
      tbg: TextEditingController(text: check.tbg),
      icp: TextEditingController(text: check.icp),
      csg: TextEditingController(text: check.csg),
      currentGasAccum: TextEditingController(text: check.currentGasAccum),
      salesGasRate: TextEditingController(text: check.salesGasRate),
      gasStatic: TextEditingController(text: check.gasStatic),
      gasDifferential: TextEditingController(text: check.gasDifferential),
      gasTemp: TextEditingController(text: check.gasTemp),
      waterSpecificGravity:
          TextEditingController(text: check.waterSpecificGravity),
      wellheadTemp: TextEditingController(text: check.wellheadTemp),
      waterTemp: TextEditingController(text: check.waterTemp),
      flareRate: TextEditingController(text: check.flareRate),
      flarePilotTemp: TextEditingController(text: check.flarePilotTemp),
      biocide: TextEditingController(text: check.biocide),
      vruGasRate: TextEditingController(text: check.vruGasRate),
      compressorInjection:
          TextEditingController(text: check.compressorInjection),
      vruSuction: TextEditingController(text: check.vruSuction),
      vruDischarge: TextEditingController(text: check.vruDischarge),
      waterTankGaugeEntries:
          waterEntries.map(_GaugeEntryControllers.fromEntry).toList(),
      oilTankGaugeEntries:
          oilEntries.map(_GaugeEntryControllers.fromEntry).toList(),
      waterHauled: TextEditingController(text: check.waterHauled),
      oilHauled: TextEditingController(text: check.oilHauled),
      waterPumped: TextEditingController(text: check.waterPumped),
      oilPumped: TextEditingController(text: check.oilPumped),
      sandRate: TextEditingController(text: check.sandRate),
      notes: TextEditingController(text: check.notes),
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

  ProductionHourlyCheck toCheck() {
    final waterEntries = waterTankGaugeEntries
        .map((item) => item.entry(gaugeEntryType))
        .toList();
    final oilEntries =
        oilTankGaugeEntries.map((item) => item.entry(gaugeEntryType)).toList();
    return ProductionHourlyCheck(
      time: time,
      well: well,
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
