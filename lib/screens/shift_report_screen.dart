import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_report_continuity_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../services/report_profile_service.dart';
import '../utils/choke_parsing.dart';
import '../utils/production_day.dart';
import '../widgets/app_header.dart';
import 'production_shift_change_screen.dart';
import 'shift_handoff_screen.dart';
import 'text_update_screen.dart';

class ShiftReportScreen extends StatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  State<ShiftReportScreen> createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends State<ShiftReportScreen> {
  static const _chartPrefsBase = 'wellwerks_production_report_chart_v1';
  static const _reportViewPrefsBase = 'wellwerks_production_report_view_v1';

  final _shiftService = ProductionShiftService();
  final _layoutService = ReportProfileService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _profileDefaults = JobProfileDefaultsService();
  final _continuityService = const ProductionReportContinuityService();

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  ReportLayoutProfile _layout = ReportProfileService().defaultProfile();
  bool _loading = true;
  int _selectedWellIndex = 0;
  Map<_ChartSeries, bool> _seriesVisibility = _defaultSeriesVisibility();
  String _pointDetail = '';
  _ChartSeries? _pointDetailSeries;
  _ReportView _reportView = _ReportView.dailyTabs;
  String _selectedProductionDay = '';

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.productionReport);
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _load();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    super.dispose();
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    var shift = await _shiftService.loadActiveShift();
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    final prefs = await SharedPreferences.getInstance();
    if (activeJob != null && shift.activeJobId != activeJob.id) {
      shift = shift.copyWith(activeJobId: activeJob.id);
      await _shiftService.saveActiveShift(shift);
    }
    final layout =
        await _layoutService.resolveProfile(shift.header.layoutProfileId);

    final prefKey = _chartPrefsKeyFor(activeJob, shift);
    final rawPrefs = prefs.getString(prefKey);
    final savedPrefs = _decodePrefs(rawPrefs);

    final rows = _resolveActiveJobRows(shift, activeJob);
    final wellOrder = _resolveWellOrder(rows, shift, activeJob);
    final selectedWellName =
        (savedPrefs['selectedWell'] as String? ?? '').trim();
    var selectedWellIndex = 0;
    if (selectedWellName.isNotEmpty) {
      final index = wellOrder.indexOf(selectedWellName);
      if (index >= 0) {
        selectedWellIndex = index;
      }
    }

    final reportPrefsRaw =
        prefs.getString(_reportViewPrefsKeyFor(activeJob, shift));
    final reportPrefs = _decodePrefs(reportPrefsRaw);
    final reportViewRaw = (reportPrefs['reportView'] as String? ?? '').trim();
    final reportView = reportViewRaw == _ReportView.timeline.name
        ? _ReportView.timeline
        : _ReportView.dailyTabs;
    final selectedProductionDayRaw =
        (reportPrefs['selectedProductionDay'] as String? ?? '').trim();
    final selectedProductionDay = selectedProductionDayRaw == '__overview__'
        ? ''
        : selectedProductionDayRaw;

    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = activeJob;
      _layout = layout;
      _selectedWellIndex = selectedWellIndex;
      _seriesVisibility = _resolvedSeriesVisibility(
        savedPrefs['visibleSeries'] as List<dynamic>?,
      );
      _reportView = reportView;
      _selectedProductionDay = selectedProductionDay;
      _loading = false;
    });
  }

  String _chartPrefsKeyFor(JobSetup? activeJob, ProductionShift shift) {
    final id = (activeJob?.id ?? shift.activeJobId).trim();
    if (id.isEmpty) return _chartPrefsBase;
    return '$_chartPrefsBase:$id';
  }

  String _reportViewPrefsKeyFor(JobSetup? activeJob, ProductionShift shift) {
    final id = (activeJob?.id ?? shift.activeJobId).trim();
    if (id.isEmpty) return _reportViewPrefsBase;
    return '$_reportViewPrefsBase:$id';
  }

  Map<String, dynamic> _decodePrefs(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _saveChartPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _chartPrefsKeyFor(_activeJob, _shift);
    final visible = _seriesVisibility.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key.id)
        .toList(growable: false);
    final selectedWell = _selectedWell;
    final payload = <String, dynamic>{
      'visibleSeries': visible,
      'selectedWell': selectedWell,
    };
    await prefs.setString(key, jsonEncode(payload));

    final reportPrefsKey = _reportViewPrefsKeyFor(_activeJob, _shift);
    final reportPayload = <String, dynamic>{
      'reportView': _reportView.name,
      'selectedProductionDay': _selectedProductionDay,
    };
    await prefs.setString(reportPrefsKey, jsonEncode(reportPayload));
  }

  static Map<_ChartSeries, bool> _defaultSeriesVisibility() {
    return <_ChartSeries, bool>{
      _ChartSeries.tubingPressure: true,
      _ChartSeries.casingPressure: true,
      _ChartSeries.gasRate: true,
      _ChartSeries.waterRate: true,
      _ChartSeries.oilRate: true,
      _ChartSeries.sandRate: false,
      _ChartSeries.choke: false,
    };
  }

  Map<_ChartSeries, bool> _resolvedSeriesVisibility(List<dynamic>? saved) {
    final defaults = _defaultSeriesVisibility();
    if (saved == null) return defaults;
    final allowed = saved.map((item) => item.toString()).toSet();
    return <_ChartSeries, bool>{
      for (final series in _ChartSeries.values)
        series: allowed.contains(series.id),
    };
  }

  List<ProductionReportRow> get _inventoryRows {
    if (_shift.inventory.productionRows.isNotEmpty) {
      return _shift.inventory.productionRows;
    }
    return _shift.savedRows;
  }

  List<ProductionReportRow> _resolveActiveJobRows(
    ProductionShift shift,
    JobSetup? activeJob,
  ) {
    final normalizedRows = _continuityService.normalizedRowsForJob(
      shift: shift,
      activeJob: activeJob,
    );
    final rows = List<ProductionReportRow>.from(normalizedRows);

    final order = _resolveWellOrderSource(shift, activeJob);
    final indexed = rows.asMap().entries.toList(growable: false);
    indexed.sort((a, b) {
      final hourCompare = a.value.hourIndex.compareTo(b.value.hourIndex);
      if (hourCompare != 0) return hourCompare;
      final ai = order.indexOf(a.value.well);
      final bi = order.indexOf(b.value.well);
      if (ai != bi) {
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      }
      return a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  List<String> _resolveWellOrderSource(
      ProductionShift shift, JobSetup? activeJob) {
    if (activeJob != null && activeJob.resolvedWellNames.isNotEmpty) {
      return activeJob.resolvedWellNames;
    }
    return shift.header.wells;
  }

  List<String> _resolveWellOrder(
    List<ProductionReportRow> rows,
    ProductionShift shift,
    JobSetup? activeJob,
  ) {
    final ordered = <String>[];
    for (final well in _resolveWellOrderSource(shift, activeJob)) {
      if (!ordered.contains(well)) ordered.add(well);
    }
    for (final row in rows) {
      if (!ordered.contains(row.well)) ordered.add(row.well);
    }
    return ordered;
  }

  List<ProductionReportRow> get _activeJobRows {
    return _resolveActiveJobRows(_shift, _activeJob);
  }

  List<String> get _wellOrder {
    return _resolveWellOrder(_activeJobRows, _shift, _activeJob);
  }

  String? get _selectedWell {
    final wells = _wellOrder;
    if (wells.isEmpty) return null;
    final clamped = _selectedWellIndex.clamp(0, wells.length - 1);
    return wells[clamped];
  }

  List<ProductionReportRow> get _rowsForSelectedWell {
    final selectedWell = _selectedWell;
    if (selectedWell == null) {
      return const [];
    }
    return _activeJobRows.where((row) => row.well == selectedWell).toList();
  }

  bool get _hasActiveJob =>
      _activeJob != null ||
      _shift.activeJobId.trim().isNotEmpty ||
      _inventoryRows.isNotEmpty;

  String get _emptyStateMessage {
    if (!_hasActiveJob) {
      return 'No active job found. Start a job first, then save Quick Round hours to view a Production Report.';
    }
    return 'No saved Production Report rows for the current active job yet. Save hours in Quick Round first.';
  }

  String _fmt(double value) {
    if (value.isNaN) return '--';
    if (value < 0) return '--';
    final rounded = value.abs() < 0.01 ? 0 : value;
    return rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  String _wholeFmt(double value) {
    if (value.isNaN) return '--';
    if (value < 0) return '--';
    return value.round().toStringAsFixed(0);
  }

  double _baseGasToDisplay(double value) {
    return _shift.inventory.gasUnit == 'mmcfd' ? value / 1000 : value;
  }

  String _gasString(String value) {
    if (value.trim().isEmpty) {
      return '--';
    }
    final parsed = double.tryParse(value.trim()) ?? -1;
    if (parsed < 0) {
      return '--';
    }
    return _fmt(_baseGasToDisplay(parsed));
  }

  String _sandRateDisplay(String value) {
    final sand = double.tryParse(value.trim()) ?? 0;
    return sand <= 0
        ? 'None'
        : (sand < 1.5
            ? 'Trace'
            : (sand < 2.5 ? 'Light' : (sand < 3.5 ? 'Medium' : 'Heavy')));
  }

  String _coolingDeltaDisplay(double value) {
    return _fmt(value);
  }

  bool _equipmentSectionSelected(String sectionName) {
    final activeJob = _activeJob;
    if (activeJob == null) return true;
    final target = sectionName.trim().toLowerCase();
    return activeJob.resolvedActiveEquipmentSections.any(
      (section) => section.trim().toLowerCase() == target,
    );
  }

  bool get _showVruSection => _equipmentSectionSelected('VRU');
  bool get _showFlareSection => _equipmentSectionSelected('FLARE / ECD');
  bool get _showGasCoolerSection => _equipmentSectionSelected('Gas Cooler');
  bool get _showWaterCoolerSection => _equipmentSectionSelected('Water Cooler');
  bool get _showCompressorSection => _equipmentSectionSelected('Compressor');
  bool get _showNotesSection {
    final raw = _activeJob?.drilloutSetup['includeNotesSection'];
    if (raw is bool) return raw;
    return true;
  }

  bool get _useOilHauled => _shift.inventory.useOilHauled;
  bool get _useWaterHauled => _shift.inventory.useWaterHauled;
  bool get _useWaterMeter => _shift.inventory.useWaterMeter;

  List<String> get _activeChemicals {
    return _activeJob?.selectedChemicals ?? const <String>[];
  }

  bool _chemicalEnabled(String name) {
    return _activeChemicals
        .any((item) => item.toLowerCase() == name.toLowerCase());
  }

  List<ProductionReportRow> _rowsForWell(String well) {
    final rows = _activeJobRows.where((row) => row.well == well).toList()
      ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
    return rows;
  }

  ProductionReportRow? _previousRowForWell(
    ProductionReportRow row,
    bool Function(ProductionReportRow row) isValid,
  ) {
    final previous = _rowsForWell(row.well)
        .where((item) => item.hourIndex < row.hourIndex && isValid(item))
        .toList();
    if (previous.isEmpty) return null;
    previous.sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
    return previous.last;
  }

  String _gasSpotForRow(ProductionReportRow row) {
    if (row.gas24HourRate.isNaN || row.gas24HourRate < 0) return '--';
    return _fmt(_baseGasToDisplay(row.gas24HourRate));
  }

  String _chk(ProductionReportRow row) {
    final value = row.choke.trim();
    if (value.isEmpty) return '-';
    return '$value ${row.chokeType}';
  }

  bool get _flareEcdGasRateEnabled {
    final setup = _activeJob?.drilloutSetup;
    final raw = setup?['flareEcdGasRateEnabled'];
    if (raw is bool) return raw;
    return true;
  }

  static const List<String> _productionFieldOrder = <String>[
    'time',
    'wellName',
    'chk',
    'tbg',
    'csg',
    'icp',
    'stat',
    'diff',
    'temp',
    'gasSpotRt',
    'waterGaugeText',
    'bwph',
    'oilGaugeText',
    'waterHauled',
    'oilHauled',
    'waterMeterReading',
    'waterMeterIncrease',
    'boph',
    'gasCoolerInTemp',
    'gasCoolerOutTemp',
    'gasCoolingDelta',
    'waterCoolerInTemp',
    'waterCoolerOutTemp',
    'waterCoolingDelta',
    'flareEcdTemp',
    'flareEcdGasRate',
    'vruGasRt',
    'vruSuct',
    'vruDisc',
    'compressorInj',
    'biocide',
    'scavenger',
    'defoamer',
    'scaleInhibitor',
    'prop',
    'propRate',
    'notes',
  ];

  List<String> get _visibleFieldKeys {
    return _productionFieldOrder.where(_fieldVisible).toList(growable: false);
  }

  bool _fieldVisible(String key) {
    switch (key) {
      case 'gasCoolerInTemp':
      case 'gasCoolerOutTemp':
      case 'gasCoolingDelta':
        return _showGasCoolerSection;
      case 'waterCoolerInTemp':
      case 'waterCoolerOutTemp':
      case 'waterCoolingDelta':
        return _showWaterCoolerSection;
      case 'flareEcdTemp':
        return _showFlareSection;
      case 'flareEcdGasRate':
        return _showFlareSection && _flareEcdGasRateEnabled;
      case 'vruGasRt':
      case 'vruSuct':
      case 'vruDisc':
      case 'vruSuction':
      case 'vruDischarge':
        return _showVruSection;
      case 'compressorInj':
        return _showCompressorSection;
      case 'biocide':
        return _chemicalEnabled('Biocide');
      case 'scavenger':
        return _chemicalEnabled('Scavenger');
      case 'defoamer':
        return _chemicalEnabled('Defoamer');
      case 'scaleInhibitor':
        return _chemicalEnabled('Scale Inhibitor');
      case 'notes':
        return _showNotesSection;
      case 'waterHauled':
        return _useWaterHauled;
      case 'oilHauled':
        return _useOilHauled;
      case 'waterMeterReading':
      case 'waterMeterIncrease':
        return _useWaterMeter;
      default:
        return true;
    }
  }

  String _headerLabel(String key) {
    final activeJob = _activeJob;
    if (activeJob != null) {
      final defaults = _profileDefaults.profileForCompany(activeJob.company);
      final profileLabel = defaults.reportLabels[key];
      if (profileLabel != null && profileLabel.trim().isNotEmpty) {
        return profileLabel;
      }
    }

    switch (key) {
      case 'wellName':
        return 'Well Name';
      case 'tbg':
        return 'Tbg';
      case 'gasSpotRt':
        return '24 HR GAS RATE';
      case 'diff':
        return 'DIFF';
      case 'stat':
        return 'STAT';
      case 'temp':
        return 'TEMP';
      case 'prop':
        return 'PROP';
      case 'propRate':
        return 'PROP / SAND RATE';
      case 'waterGaugeText':
        return 'WATER TANKS';
      case 'oilGaugeText':
        return 'OIL TANKS';
      case 'waterHauled':
        return 'WATER HAULED';
      case 'oilHauled':
        return 'OIL HAULED';
      case 'waterMeterReading':
        return 'WATER METER READING';
      case 'waterMeterIncrease':
        return 'WATER METER INCREASE';
      case 'gasCoolerInTemp':
        return 'GAS IN TEMP';
      case 'gasCoolerOutTemp':
        return 'GAS OUT TEMP';
      case 'gasCoolingDelta':
        return 'GAS COOLING DELTA';
      case 'waterCoolerInTemp':
        return 'WATER IN TEMP';
      case 'waterCoolerOutTemp':
        return 'WATER OUT TEMP';
      case 'waterCoolingDelta':
        return 'WATER COOLING DELTA';
      case 'wht':
        return 'WHT';
      case 'flareEcdGasRate':
        return 'FLARE / ECD GAS RATE';
      case 'flareEcdTemp':
        return 'FLARE / ECD TEMP';
      case 'biocide':
        return 'BIOCIDE';
      case 'scavenger':
        return 'SCAVENGER';
      case 'defoamer':
        return 'DEFOAMER';
      case 'scaleInhibitor':
        return 'SCALE INHIBITOR';
      case 'vruGasRt':
        return 'VRU GAS RT';
      default:
        return _layout.reportFields
            .firstWhere((f) => f.key == key,
                orElse: () => ReportField(key: key, label: key))
            .label;
    }
  }

  String _valueFor(ProductionReportRow row, String key) {
    switch (key) {
      case 'time':
        return row.time;
      case 'well':
        return row.well;
      case 'wellName':
        return row.well;
      case 'csg':
        return row.csg;
      case 'tbg':
        return row.tbg;
      case 'icp':
        return row.icp;
      case 'chk':
        return _chk(row);
      case 'bwph':
        return _wholeFmt(row.waterProduction);
      case 'boph':
        return _wholeFmt(row.oilProduction);
      case 'gasSpotRt':
        return _gasSpotForRow(row);
      case 'diff':
        return row.gasDifferential;
      case 'stat':
        return row.gasStatic;
      case 'temp':
        return row.gasTemp;
      case 'waterGaugeText':
        return row.waterGaugeText;
      case 'oilGaugeText':
        return row.oilGaugeText;
      case 'waterHauled':
        return _fmt(row.waterHauled);
      case 'oilHauled':
        return _fmt(row.oilHauled);
      case 'waterMeterReading':
        return _fmt(row.currentWaterMeter);
      case 'waterMeterIncrease':
        final previous = _previousRowForWell(
          row,
          (item) =>
              item.waterMeasurementMethod ==
              ProductionWellCheckData.measurementMeter,
        );
        if (previous == null || row.currentWaterMeter < 0) return '--';
        return _fmt(row.currentWaterMeter - previous.currentWaterMeter);
      case 'gasCoolerInTemp':
        return _showGasCoolerSection ? row.gasCoolerInTemp : '';
      case 'gasCoolerOutTemp':
        return _showGasCoolerSection ? row.gasCoolerOutTemp : '';
      case 'gasCoolingDelta':
        return _showGasCoolerSection
            ? _coolingDeltaDisplay(row.gasCoolingDelta)
            : '';
      case 'waterCoolerInTemp':
        return _showWaterCoolerSection ? row.waterCoolerInTemp : '';
      case 'waterCoolerOutTemp':
        return _showWaterCoolerSection ? row.waterCoolerOutTemp : '';
      case 'waterCoolingDelta':
        return _showWaterCoolerSection
            ? _coolingDeltaDisplay(row.waterCoolingDelta)
            : '';
      case 'prop':
        return _sandRateDisplay(row.sandRate);
      case 'propRate':
        return row.sandOptionalRate;
      case 'h2oSg':
        return row.waterSpecificGravity;
      case 'wht':
        return row.wellheadTemp;
      case 'flareRt':
        return _gasString(row.flareRate);
      case 'flarePilotTemp':
        return row.flarePilotTemp;
      case 'flareEcdGasRate':
        if (!_showFlareSection) return '';
        if (!_flareEcdGasRateEnabled) return '';
        return _gasString(row.flareRate);
      case 'flareEcdTemp':
        if (!_showFlareSection) return '';
        return row.flarePilotTemp;
      case 'biocide':
        return row.biocide;
      case 'scavenger':
        return row.scavenger;
      case 'defoamer':
        return row.defoamer;
      case 'scaleInhibitor':
        return row.scaleInhibitor;
      case 'vruGasRt':
        if (!_showVruSection) return '';
        return _gasString(row.vruGasRate);
      case 'vruSuct':
        if (!_showVruSection) return '';
        return row.vruSuction;
      case 'vruDisc':
        if (!_showVruSection) return '';
        return row.vruDischarge;
      case 'compressorInj':
        if (!_showCompressorSection) return '';
        return _gasString(row.compressorInjection);
      case 'vruSuction':
        if (!_showVruSection) return '';
        return row.vruSuction;
      case 'vruDischarge':
        if (!_showVruSection) return '';
        return row.vruDischarge;
      case 'notes':
        if (!_showNotesSection) return '';
        return row.notes;
      default:
        return '';
    }
  }

  String get _reportText {
    final rows = _rowsForSelectedWell;
    if (rows.isEmpty) {
      return _emptyStateMessage;
    }

    final lines = <String>['Production Report (${_layout.name})', ''];
    for (final row in rows) {
      lines.add('${row.time} | ${row.well}');
      for (final key in _visibleFieldKeys) {
        final value = _valueFor(row, key);
        if (value.trim().isEmpty) {
          continue;
        }
        lines.add('${_headerLabel(key)}: $value');
      }
      if (row != rows.last) {
        lines.add('');
      }
    }
    return lines.join('\n');
  }

  String get _reportCsv {
    final headers = _visibleFieldKeys.map(_headerLabel).toList();
    final csvRows = <List<String>>[
      headers,
      for (final row in _rowsForSelectedWell)
        _visibleFieldKeys.map((key) => _valueFor(row, key)).toList(),
    ];

    return csvRows
        .map((row) =>
            row.map((value) => '"${value.replaceAll('"', '""')}"').join(','))
        .join('\n');
  }

  Future<void> _openHandoffFromActions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShiftHandoffScreen()),
    );
    await _load();
  }

  Future<void> _openTextUpdateFromActions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TextUpdateScreen()),
    );
    await _load();
  }

  Future<void> _openShiftChangeFromActions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProductionShiftChangeScreen()),
    );
    await _load();
  }

  Future<void> _shareReport() async {
    if (_activeJobRows.isEmpty) return;
    await Share.share(
      _reportText,
      subject: 'Production Report',
    );
  }

  Future<void> _exportReport() async {
    final file = await _shiftService.exportReportCsv(
      fileName: 'production_report.csv',
      csv: _reportCsv,
    );
    await Share.shareXFiles([XFile(file.path)], text: 'Production Report');
  }

  DataColumn _column(String label) => DataColumn(
        label: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  DataCell _cell(String value) => DataCell(Text(value.isEmpty ? '-' : value));

  List<({String id, String label, String sourceKey, String? tankId})>
      _dayTableColumns(List<ProductionReportRow> rows) {
    final columns =
        <({String id, String label, String sourceKey, String? tankId})>[];

    for (final key in _visibleFieldKeys) {
      if (key == 'waterGaugeText') {
        final waterTankIds = _tankColumnIdsForRows(rows, key, 'WT');
        if (waterTankIds.isEmpty) {
          columns.add((
            id: key,
            label: _headerLabel(key),
            sourceKey: key,
            tankId: null,
          ));
        } else {
          for (final tankId in waterTankIds) {
            columns.add((
              id: 'water-$tankId',
              label: tankId,
              sourceKey: key,
              tankId: tankId,
            ));
          }
        }
        continue;
      }

      if (key == 'oilGaugeText') {
        final oilTankIds = _tankColumnIdsForRows(rows, key, 'OT');
        if (oilTankIds.isEmpty) {
          columns.add((
            id: key,
            label: _headerLabel(key),
            sourceKey: key,
            tankId: null,
          ));
        } else {
          for (final tankId in oilTankIds) {
            columns.add((
              id: 'oil-$tankId',
              label: tankId,
              sourceKey: key,
              tankId: tankId,
            ));
          }
        }
        continue;
      }

      columns.add((
        id: key,
        label: _headerLabel(key),
        sourceKey: key,
        tankId: null,
      ));
    }

    return columns;
  }

  List<String> _tankColumnIdsForRows(
    List<ProductionReportRow> rows,
    String sourceKey,
    String prefix,
  ) {
    final found = <String>{};
    for (final row in rows) {
      final parsed = _parseTankGaugeColumns(
        _valueFor(row, sourceKey),
        prefix: prefix,
      );
      found.addAll(parsed.keys);
    }
    final ids = found.toList(growable: false);
    ids.sort((a, b) {
      final ai = int.tryParse(a.replaceFirst(prefix, '')) ?? 0;
      final bi = int.tryParse(b.replaceFirst(prefix, '')) ?? 0;
      return ai.compareTo(bi);
    });
    return ids;
  }

  Map<String, String> _parseTankGaugeColumns(
    String raw, {
    required String prefix,
  }) {
    final values = <String, String>{};
    final text = raw.trim();
    if (text.isEmpty) return values;

    for (final segment in text.split(',')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final separator = trimmed.indexOf(':');
      if (separator <= 0) continue;

      final name = trimmed.substring(0, separator).trim();
      var value = trimmed.substring(separator + 1).trim();
      if (value.isEmpty) continue;

      final numberMatch = RegExp(r'(\d+)').firstMatch(name);
      if (numberMatch == null) continue;
      final tankId = '$prefix${numberMatch.group(1)!}';
      values[tankId] = value;
    }

    return values;
  }

  String _dayTableValueForColumn(
    ProductionReportRow row,
    ({String id, String label, String sourceKey, String? tankId}) column,
  ) {
    if (column.tankId == null) {
      return _valueFor(row, column.sourceKey);
    }

    final prefix = column.sourceKey == 'waterGaugeText' ? 'WT' : 'OT';
    final parsed = _parseTankGaugeColumns(
      _valueFor(row, column.sourceKey),
      prefix: prefix,
    );
    return parsed[column.tankId] ?? '';
  }

  Widget _buildDayTable(List<ProductionReportRow> rows) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No entries for this production day.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    if (_visibleFieldKeys.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Active layout has no report columns enabled.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final columns = _dayTableColumns(rows);
    if (columns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Active layout has no report columns enabled.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final column in columns) _column(column.label),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final column in columns)
                  _cell(_dayTableValueForColumn(row, column)),
              ],
            ),
        ],
      ),
    );
  }

  String _prettyProductionDay(String dayKey) {
    final parsed = DateTime.tryParse(dayKey);
    if (parsed == null) return dayKey;
    return DateFormat('MMM d').format(parsed);
  }

  Widget _buildOverviewCard(List<ProductionReportRow> rows) {
    final grouped = _continuityService.groupByProductionDay(rows);
    final dayCount = grouped.length;
    final first = rows
        .map((row) => DateTime.tryParse(row.originalTimestampIso))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final last = rows
        .map((row) => DateTime.tryParse(row.originalTimestampIso))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    final totalWater =
        rows.fold<double>(0, (sum, row) => sum + row.waterProduction);
    final totalOil =
        rows.fold<double>(0, (sum, row) => sum + row.oilProduction);
    final totalGas = rows.fold<double>(0, (sum, row) => sum + row.hourlyGas);
    final totalOilHauled =
        rows.fold<double>(0, (sum, row) => sum + row.oilHauled);
    final totalOilPumped =
        rows.fold<double>(0, (sum, row) => sum + row.oilPumped);

    final customer = (_activeJob?.company ?? _shift.header.company).trim();
    final jobName = (_activeJob?.padName ?? _shift.header.pad).trim();
    final selectedWell = _selectedWell?.trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overview',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text('Customer: ${customer.isEmpty ? '-' : customer}'),
            Text('Job: ${jobName.isEmpty ? '-' : jobName}'),
            Text('Well: ${selectedWell.isEmpty ? '-' : selectedWell}'),
            Text(
              'Current Production Day: ${_prettyProductionDay(productionDayKey(DateTime.now()))}',
            ),
            Text('Production Days: $dayCount'),
            Text(
              'First Entry: ${first == null ? '-' : DateFormat('MMM d, h:mm a').format(first)}',
            ),
            Text(
              'Latest Entry: ${last == null ? '-' : DateFormat('MMM d, h:mm a').format(last)}',
            ),
            Text('Total Water Produced: ${_wholeFmt(totalWater)} bbl'),
            Text('Total Oil Produced: ${_wholeFmt(totalOil)} bbl'),
            Text('Total Gas Produced: ${_wholeFmt(totalGas)}'),
            Text('Total Oil Hauled: ${_wholeFmt(totalOilHauled)} bbl'),
            Text('Total Oil Pumped: ${_wholeFmt(totalOilPumped)} bbl'),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyTabsContent() {
    final selectedRows = _rowsForSelectedWell;
    final grouped = _continuityService.groupByProductionDay(selectedRows);
    final dayKeys = grouped.keys.toList()..sort();
    final selectedDay = dayKeys.contains(_selectedProductionDay)
        ? _selectedProductionDay
        : (dayKeys.isEmpty ? '' : dayKeys.last);

    final chips = <Widget>[
      ChoiceChip(
        label: const Text('Overview'),
        selected: _selectedProductionDay == '__overview__' ||
            (dayKeys.isEmpty && _selectedProductionDay.isEmpty),
        onSelected: (_) {
          setState(() => _selectedProductionDay = '__overview__');
          _saveChartPrefs();
        },
      ),
      for (final key in dayKeys)
        ChoiceChip(
          label: Text(_prettyProductionDay(key)),
          selected: _selectedProductionDay == key ||
              (_selectedProductionDay.isEmpty &&
                  key == selectedDay &&
                  _selectedProductionDay != '__overview__'),
          onSelected: (_) {
            setState(() => _selectedProductionDay = key);
            _saveChartPrefs();
          },
        ),
    ];

    final showOverview = _selectedProductionDay == '__overview__' ||
        (dayKeys.isEmpty && _selectedProductionDay.isEmpty);
    final activeDay =
        _selectedProductionDay.isEmpty ? selectedDay : _selectedProductionDay;
    final rowsForDay = showOverview
        ? const <ProductionReportRow>[]
        : (grouped[activeDay] ?? const <ProductionReportRow>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final chip in chips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: chip,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (showOverview)
          _buildOverviewCard(selectedRows)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _buildDayTable(rowsForDay),
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineContent() {
    final grouped =
        _continuityService.groupByProductionDay(_rowsForSelectedWell);
    final dayKeys = grouped.keys.toList()..sort();
    if (dayKeys.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No timeline entries yet.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in dayKeys) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              '${_prettyProductionDay(day).toUpperCase()} PRODUCTION DAY',
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final row in grouped[day] ?? const <ProductionReportRow>[])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${row.time} • ${row.well}'),
              subtitle: Text(
                'Oil ${_wholeFmt(row.oilProduction)} bbl/hr • Water ${_wholeFmt(row.waterProduction)} bbl/hr • Gas ${_wholeFmt(row.hourlyGas)}',
              ),
            ),
          const Divider(),
        ],
      ],
    );
  }

  void _goToPreviousWell() {
    if (_selectedWellIndex <= 0) {
      return;
    }
    setState(() => _selectedWellIndex -= 1);
    _saveChartPrefs();
  }

  void _goToNextWell() {
    final wells = _wellOrder;
    if (_selectedWellIndex >= wells.length - 1) {
      return;
    }
    setState(() => _selectedWellIndex += 1);
    _saveChartPrefs();
  }

  DateTime? _parseReadingTime(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    const formats = [
      'h a',
      'h:mm a',
      'hh:mm a',
      'H:mm',
      'HH:mm',
    ];
    for (final format in formats) {
      try {
        return DateFormat(format).parseStrict(raw);
      } catch (_) {
        // Try next.
      }
    }
    return null;
  }

  String _conciseTimeLabel(String time) {
    final parsed = _parseReadingTime(time);
    if (parsed != null) {
      return DateFormat('h a').format(parsed);
    }
    return time.trim().isEmpty ? '--' : time.trim();
  }

  String _specificTimeLabel(String time) {
    final parsed = _parseReadingTime(time);
    if (parsed != null) {
      return DateFormat('h:mm a').format(parsed);
    }
    return time.trim().isEmpty ? '--' : time.trim();
  }

  List<_ChartPoint> _buildChartPoints(List<ProductionReportRow> rows) {
    final concise = rows.map((row) => _conciseTimeLabel(row.time)).toList();
    final totalByLabel = <String, int>{};
    for (final label in concise) {
      totalByLabel[label] = (totalByLabel[label] ?? 0) + 1;
    }
    final seenByLabel = <String, int>{};

    final points = <_ChartPoint>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final base = concise[i];
      final seen = (seenByLabel[base] ?? 0) + 1;
      seenByLabel[base] = seen;
      var axisLabel = base;
      if ((totalByLabel[base] ?? 0) > 1) {
        final specific = _specificTimeLabel(row.time);
        axisLabel = specific == base ? '$base #$seen' : specific;
      }
      points.add(_ChartPoint(
        x: i.toDouble(),
        axisLabel: axisLabel,
        row: row,
      ));
    }
    return points;
  }

  double? _tryParsePositiveOrZero(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value < 0) return null;
    return value;
  }

  double? _seriesNumericValue(_ChartSeries series, ProductionReportRow row) {
    switch (series) {
      case _ChartSeries.tubingPressure:
        return _tryParsePositiveOrZero(row.tbg);
      case _ChartSeries.casingPressure:
        return _tryParsePositiveOrZero(row.csg);
      case _ChartSeries.gasRate:
        return row.hourlyGas >= 0 ? row.hourlyGas : null;
      case _ChartSeries.waterRate:
        return row.waterProduction >= 0 ? row.waterProduction : null;
      case _ChartSeries.oilRate:
        return row.oilProduction >= 0 ? row.oilProduction : null;
      case _ChartSeries.sandRate:
        return _tryParsePositiveOrZero(row.sandRate);
      case _ChartSeries.choke:
        return parseChokePlotValue(row.choke);
    }
  }

  String _seriesExactValue(_ChartSeries series, ProductionReportRow row) {
    switch (series) {
      case _ChartSeries.tubingPressure:
        return row.tbg.trim();
      case _ChartSeries.casingPressure:
        return row.csg.trim();
      case _ChartSeries.gasRate:
        return row.hourlyGas.toString();
      case _ChartSeries.waterRate:
        return row.waterProduction.toString();
      case _ChartSeries.oilRate:
        return row.oilProduction.toString();
      case _ChartSeries.sandRate:
        return row.sandRate.trim();
      case _ChartSeries.choke:
        return row.choke.trim();
    }
  }

  String _seriesUnit(_ChartSeries series) {
    switch (series) {
      case _ChartSeries.tubingPressure:
      case _ChartSeries.casingPressure:
        return 'psi';
      case _ChartSeries.gasRate:
        return _shift.inventory.gasUnit == 'mmcfd' ? 'mmcf/d' : 'mcf/d';
      case _ChartSeries.waterRate:
      case _ChartSeries.oilRate:
        return 'bbl/hr';
      case _ChartSeries.sandRate:
        return '';
      case _ChartSeries.choke:
        return '';
    }
  }

  String _seriesLabel(_ChartSeries series) {
    switch (series) {
      case _ChartSeries.tubingPressure:
        return 'Tubing Pressure';
      case _ChartSeries.casingPressure:
        return 'Casing Pressure';
      case _ChartSeries.gasRate:
        return 'Gas Rate';
      case _ChartSeries.waterRate:
        return 'Water Rate';
      case _ChartSeries.oilRate:
        return 'Oil Rate';
      case _ChartSeries.sandRate:
        return 'Sand Rate';
      case _ChartSeries.choke:
        return 'Choke';
    }
  }

  _AxisGroup _axisGroup(_ChartSeries series) {
    switch (series) {
      case _ChartSeries.tubingPressure:
      case _ChartSeries.casingPressure:
      case _ChartSeries.gasRate:
        return _AxisGroup.left;
      case _ChartSeries.waterRate:
      case _ChartSeries.oilRate:
      case _ChartSeries.sandRate:
      case _ChartSeries.choke:
        return _AxisGroup.right;
    }
  }

  // Centralized fixed color mapping for all production chart series UI.
  static const Map<_ChartSeries, Color> _seriesColors = {
    _ChartSeries.tubingPressure: Colors.yellow,
    _ChartSeries.casingPressure: Colors.red,
    _ChartSeries.gasRate: Colors.green,
    _ChartSeries.waterRate: Colors.blue,
    _ChartSeries.oilRate: Colors.black,
    _ChartSeries.sandRate: Colors.brown,
    _ChartSeries.choke: Colors.orange,
  };

  Color _seriesColor(_ChartSeries series) {
    return _seriesColors[series] ?? Colors.white;
  }

  Color _seriesStrokeColor(_ChartSeries series, ColorScheme scheme) {
    if (series == _ChartSeries.oilRate) {
      return Colors.white.withValues(alpha: 0.85);
    }
    return scheme.surface;
  }

  Shadow _seriesLineShadow(_ChartSeries series) {
    if (series == _ChartSeries.oilRate) {
      return Shadow(
        color: Colors.white.withValues(alpha: 0.68),
        blurRadius: 3.0,
        offset: Offset.zero,
      );
    }
    return const Shadow(color: Colors.transparent);
  }

  Widget _seriesColorDot(
    _ChartSeries series,
    ColorScheme scheme, {
    double size = 12,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _seriesColor(series),
        shape: BoxShape.circle,
        border: Border.all(
          color: _seriesStrokeColor(series, scheme),
          width: 1.1,
        ),
      ),
    );
  }

  Widget _chartLegendControl() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('production-chart-card'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chart Lines',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final series in _ChartSeries.values)
                  FilterChip(
                    key: Key('chart-series-${series.id}'),
                    avatar: _seriesColorDot(series, scheme),
                    label: Text(_seriesLabel(series)),
                    selected: _seriesVisibility[series] ?? false,
                    onSelected: (selected) {
                      setState(() {
                        _seriesVisibility = {
                          ..._seriesVisibility,
                          series: selected,
                        };
                      });
                      _saveChartPrefs();
                    },
                    selectedColor: _seriesColor(series).withValues(alpha: 0.25),
                    checkmarkColor: _seriesColor(series),
                    side: BorderSide(
                      color: (_seriesVisibility[series] ?? false)
                          ? _seriesColor(series)
                          : scheme.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  key: const Key('chart-select-all'),
                  onPressed: () {
                    setState(() {
                      _seriesVisibility = {
                        for (final series in _ChartSeries.values) series: true,
                      };
                    });
                    _saveChartPrefs();
                  },
                  child: const Text('Select All'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('chart-clear-all'),
                  onPressed: () {
                    setState(() {
                      _seriesVisibility = {
                        for (final series in _ChartSeries.values) series: false,
                      };
                    });
                    _saveChartPrefs();
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyChartState(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          message,
          key: const Key('production-chart-empty-state'),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildChart() {
    final rows = _rowsForSelectedWell;
    if (rows.isEmpty) {
      return _emptyChartState('No production readings available yet.');
    }

    final visibleSeries = _ChartSeries.values
        .where((series) => _seriesVisibility[series] ?? false)
        .toList(growable: false);
    if (visibleSeries.isEmpty) {
      return _emptyChartState('Select at least one chart line.');
    }

    final points = _buildChartPoints(rows);
    final scheme = Theme.of(context).colorScheme;
    final leftValues = <double>[];
    final rightValues = <double>[];

    final seriesCounts = <_ChartSeries, int>{};
    final builtSeries = <_BuiltChartSeries>[];

    for (final series in visibleSeries) {
      final values = <double>[];
      for (final point in points) {
        final value = _seriesNumericValue(series, point.row);
        if (value != null) {
          values.add(value);
        }
      }
      if (_axisGroup(series) == _AxisGroup.left) {
        leftValues.addAll(values);
      } else {
        rightValues.addAll(values);
      }
    }

    final transform = _AxisTransform.build(leftValues, rightValues);

    final lineBars = <LineChartBarData>[];
    for (final series in visibleSeries) {
      final actualByX = <int, double>{};
      final exactByX = <int, String>{};
      final spots = <FlSpot>[];
      for (var i = 0; i < points.length; i++) {
        final point = points[i];
        final value = _seriesNumericValue(series, point.row);
        if (value == null) {
          if (series == _ChartSeries.choke) {
            spots.add(FlSpot.nullSpot);
          }
          continue;
        }
        actualByX[i] = value;
        exactByX[i] = _seriesExactValue(series, point.row);
        final y = _axisGroup(series) == _AxisGroup.left
            ? value
            : transform.rightToLeft(value);
        spots.add(FlSpot(point.x, y));
      }
      seriesCounts[series] = spots.length;
      seriesCounts[series] = actualByX.length;

      final color = _seriesColor(series);
      builtSeries.add(_BuiltChartSeries(
        series: series,
        barData: LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: 2.8,
          shadow: _seriesLineShadow(series),
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 3.2,
              color: color,
              strokeWidth: 1.2,
              strokeColor: _seriesStrokeColor(series, scheme),
            ),
          ),
          belowBarData: BarAreaData(show: false),
        ),
        actualByX: actualByX,
        exactByX: exactByX,
      ));
      lineBars.add(builtSeries.last.barData);
    }

    final pointsWithData = <int>{
      for (final series in builtSeries) ...series.actualByX.keys,
    }.length;

    final chartWidth =
        (points.length * 72).toDouble().clamp(320.0, 4200.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hourly Trend',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Left axis: Tubing Pressure, Casing Pressure, Gas Rate\nRight axis: Water Rate, Oil Rate, Sand Rate, Choke',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 320,
                child: LineChart(
                  key: const Key('production-line-chart'),
                  LineChartData(
                    minX: 0,
                    maxX: points.isEmpty ? 1 : (points.length - 1).toDouble(),
                    minY: transform.plotMin,
                    maxY: transform.plotMax,
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchCallback: (event, response) {
                        if (response == null ||
                            response.lineBarSpots == null ||
                            response.lineBarSpots!.isEmpty) {
                          return;
                        }
                        final spot = response.lineBarSpots!.first;
                        final series = builtSeries[spot.barIndex];
                        final index = spot.x.round();
                        if (index < 0 || index >= points.length) {
                          return;
                        }
                        final point = points[index];
                        final exact = series.exactByX[index] ?? '--';
                        final unit = _seriesUnit(series.series);
                        final suffix = unit.isEmpty ? '' : ' $unit';
                        final detail =
                            '${point.row.time} • ${_seriesLabel(series.series)}: $exact$suffix';
                        if (!mounted) return;
                        setState(() {
                          _pointDetail = detail;
                          _pointDetailSeries = series.series;
                        });
                      },
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) {
                          return spots.map((spot) {
                            final series = builtSeries[spot.barIndex];
                            final index = spot.x.round();
                            final point = points[index];
                            final exact = series.exactByX[index] ?? '--';
                            final unit = _seriesUnit(series.series);
                            final suffix = unit.isEmpty ? '' : ' $unit';
                            return LineTooltipItem(
                              '${point.row.time}\n${_seriesLabel(series.series)}: $exact$suffix',
                              TextStyle(
                                color: _seriesColor(series.series),
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          }).toList(growable: false);
                        },
                      ),
                    ),
                    lineBarsData: lineBars,
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.round();
                            if (index < 0 || index >= points.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                points[index].axisLabel,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: Text(
                          'Pressure / Gas',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 50,
                          getTitlesWidget: (value, meta) => Text(
                            transform.leftLabel(value),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      rightTitles: AxisTitles(
                        axisNameWidget: Text(
                          'Rates / Choke',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 56,
                          getTitlesWidget: (value, meta) => Text(
                            transform.rightLabel(value),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval:
                          (transform.plotMax - transform.plotMin) / 4,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: scheme.outlineVariant.withValues(alpha: 0.45),
                        strokeWidth: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              key: const Key('production-chart-legend-wrap'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final series in visibleSeries)
                  Chip(
                    key: Key('chart-legend-${series.id}'),
                    avatar: _seriesColorDot(series, scheme),
                    label: Text(
                      '${_seriesLabel(series)} (${seriesCounts[series] ?? 0})',
                    ),
                  ),
              ],
            ),
            if (_pointDetail.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  key: const Key('production-chart-point-detail'),
                  children: [
                    _seriesColorDot(
                      _pointDetailSeries ?? _ChartSeries.tubingPressure,
                      scheme,
                      size: 10,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pointDetail,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            if (pointsWithData <= 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Only one reading is available. Add another reading to create a trend line.',
                  key: const Key('production-chart-single-reading-state'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportTab(String summary) {
    return ListView(
      key: const Key('production-report-tab-report'),
      padding: const EdgeInsets.all(18),
      children: [
        _activeJobBanner(),
        _wellNavigationControls(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<_ReportView>(
                  segments: const [
                    ButtonSegment<_ReportView>(
                      value: _ReportView.dailyTabs,
                      label: Text('Daily Tabs'),
                    ),
                    ButtonSegment<_ReportView>(
                      value: _ReportView.timeline,
                      label: Text('Timeline'),
                    ),
                  ],
                  selected: {_reportView},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _reportView = selection.first;
                    });
                    _saveChartPrefs();
                  },
                ),
                const SizedBox(height: 10),
                if (summary.isNotEmpty)
                  Text(
                    summary,
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (summary.isNotEmpty) const SizedBox(height: 8),
                Text(
                  'Layout: ${_layout.name}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved hours: ${_rowsForSelectedWell.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _reportView == _ReportView.dailyTabs
                ? _buildDailyTabsContent()
                : _buildTimelineContent(),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required String keyName,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilledButton.tonalIcon(
        key: Key(keyName),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _pinnedActionsSection() {
    final colors = Theme.of(context).colorScheme;
    final disabled = _activeJobRows.isEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Actions',
                style: TextStyle(
                  color: Color(0xFFCDA56A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _actionButton(
                      keyName: 'production-report-action-shift-handoff',
                      label: 'SHIFT HANDOFF',
                      icon: Icons.compare_arrows,
                      onPressed: disabled ? null : _openHandoffFromActions,
                    ),
                    _actionButton(
                      keyName: 'production-report-action-text-update',
                      label: 'TEXT UPDATE',
                      icon: Icons.sms_outlined,
                      onPressed: disabled ? null : _openTextUpdateFromActions,
                    ),
                    _actionButton(
                      keyName: 'production-report-action-shift-change',
                      label: 'SHIFT CHANGE',
                      icon: Icons.change_circle_outlined,
                      onPressed: disabled ? null : _openShiftChangeFromActions,
                    ),
                    _actionButton(
                      keyName: 'production-report-action-share',
                      label: 'Share',
                      icon: Icons.share_outlined,
                      onPressed: disabled ? null : _shareReport,
                    ),
                    _actionButton(
                      keyName: 'production-report-action-export',
                      label: 'Export',
                      icon: Icons.ios_share,
                      onPressed: disabled ? null : _exportReport,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartTab(String summary) {
    return ListView(
      key: const Key('production-report-tab-chart'),
      padding: const EdgeInsets.all(18),
      children: [
        _activeJobBanner(),
        _wellNavigationControls(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.isNotEmpty)
                  Text(
                    summary,
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (summary.isNotEmpty) const SizedBox(height: 8),
                const Text(
                  'Chart source: current Production Report rows for selected well only',
                  key: Key('production-chart-source-note'),
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        _chartLegendControl(),
        _buildChart(),
      ],
    );
  }

  Widget _wellNavigationControls() {
    final wells = _wellOrder;
    if (wells.isEmpty) {
      return const SizedBox.shrink();
    }
    final selectedWell = _selectedWell ?? wells.first;
    final canGoPrevious = _selectedWellIndex > 0;
    final canGoNext = _selectedWellIndex < wells.length - 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canGoPrevious ? _goToPreviousWell : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous Well'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selectedWell,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFCDA56A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canGoNext ? _goToNextWell : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next Well'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeJobBanner() {
    final activeJob = _activeJob;
    if (activeJob == null) {
      if (_inventoryRows.isNotEmpty || _shift.activeJobId.trim().isNotEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active Job',
                  style: TextStyle(
                    color: Color(0xFFCDA56A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Linked to active shift data (${_inventoryRows.length} saved row${_inventoryRows.length == 1 ? '' : 's'}).',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      }
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Job',
                style: TextStyle(
                  color: Color(0xFFCDA56A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No active job found. Start a job first to view the current Production Report safely.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Job',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              activeJob.company.trim().isEmpty
                  ? 'No company entered'
                  : activeJob.company,
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _jobChip('Pad', activeJob.padName),
                _jobChip(
                  activeJob.isMultiWellJob ? 'Wells' : 'Well',
                  activeJob.isMultiWellJob
                      ? activeJob.resolvedWellNames.join(', ')
                      : activeJob.primaryWell,
                ),
                _jobChip(
                    'Type', _profileDefaults.jobTypeLabel(activeJob.jobType)),
                _jobChip('Shift', activeJob.shift),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobChip(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        '$label: ${value.trim().isEmpty ? 'Not entered' : value.trim()}',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Production Report', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final header = _shift.header;
    final summary = [header.company, header.pad]
        .where((item) => item.trim().isNotEmpty)
        .join(' • ');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const AppHeader(title: 'Production Report', showBack: true),
        bottomNavigationBar: _pinnedActionsSection(),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).cardColor,
              child: const TabBar(
                key: Key('production-report-tabs'),
                tabs: [
                  Tab(text: 'Report'),
                  Tab(text: 'Chart'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildReportTab(summary),
                  _buildChartTab(summary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChartSeries {
  tubingPressure('tbg'),
  casingPressure('csg'),
  gasRate('gasRate'),
  waterRate('waterRate'),
  oilRate('oilRate'),
  sandRate('sandRate'),
  choke('choke');

  const _ChartSeries(this.id);
  final String id;
}

enum _ReportView { dailyTabs, timeline }

enum _AxisGroup { left, right }

class _ChartPoint {
  const _ChartPoint({
    required this.x,
    required this.axisLabel,
    required this.row,
  });

  final double x;
  final String axisLabel;
  final ProductionReportRow row;
}

class _BuiltChartSeries {
  const _BuiltChartSeries({
    required this.series,
    required this.barData,
    required this.actualByX,
    required this.exactByX,
  });

  final _ChartSeries series;
  final LineChartBarData barData;
  final Map<int, double> actualByX;
  final Map<int, String> exactByX;
}

class _AxisTransform {
  const _AxisTransform({
    required this.leftMin,
    required this.leftMax,
    required this.rightMin,
    required this.rightMax,
    required this.plotMin,
    required this.plotMax,
  });

  final double leftMin;
  final double leftMax;
  final double rightMin;
  final double rightMax;
  final double plotMin;
  final double plotMax;

  static _AxisTransform build(
      List<double> leftValues, List<double> rightValues) {
    final rawLeftMin = leftValues.isEmpty
        ? (rightValues.isEmpty
            ? 0.0
            : rightValues.reduce((a, b) => a < b ? a : b))
        : leftValues.reduce((a, b) => a < b ? a : b);
    final rawLeftMax = leftValues.isEmpty
        ? (rightValues.isEmpty
            ? 1.0
            : rightValues.reduce((a, b) => a > b ? a : b))
        : leftValues.reduce((a, b) => a > b ? a : b);
    final rawRightMin = rightValues.isEmpty
        ? rawLeftMin
        : rightValues.reduce((a, b) => a < b ? a : b);
    final rawRightMax = rightValues.isEmpty
        ? rawLeftMax
        : rightValues.reduce((a, b) => a > b ? a : b);

    final paddedLeft = _paddedRange(
      rawLeftMin,
      rawLeftMax,
      clampNonNegative: rawLeftMin >= 0,
    );
    final paddedRight = _paddedRange(
      rawRightMin,
      rawRightMax,
      clampNonNegative: rawRightMin >= 0,
    );

    return _AxisTransform(
      leftMin: paddedLeft.$1,
      leftMax: paddedLeft.$2,
      rightMin: paddedRight.$1,
      rightMax: paddedRight.$2,
      plotMin: paddedLeft.$1,
      plotMax: paddedLeft.$2,
    );
  }

  static (double, double) _paddedRange(
    double rawMin,
    double rawMax, {
    required bool clampNonNegative,
  }) {
    final span = rawMax - rawMin;
    final safeSpan = span.abs() < 0.000001
        ? (rawMax.abs() < 1 ? 1.0 : rawMax.abs() * 0.2)
        : span.abs();
    final pad = safeSpan * 0.1;

    var min = rawMin - pad;
    var max = rawMax + pad;

    if (clampNonNegative && min < 0) {
      min = 0;
    }
    if (max <= min) {
      max = min + 1;
    }
    return (min, max);
  }

  double rightToLeft(double rightValue) {
    final rightRange =
        (rightMax - rightMin).abs() < 0.000001 ? 1.0 : rightMax - rightMin;
    final leftRange =
        (leftMax - leftMin).abs() < 0.000001 ? 1.0 : leftMax - leftMin;
    final ratio = (rightValue - rightMin) / rightRange;
    return leftMin + (ratio * leftRange);
  }

  double leftToRight(double leftValue) {
    final leftRange =
        (leftMax - leftMin).abs() < 0.000001 ? 1.0 : leftMax - leftMin;
    final rightRange =
        (rightMax - rightMin).abs() < 0.000001 ? 1.0 : rightMax - rightMin;
    final ratio = (leftValue - leftMin) / leftRange;
    return rightMin + (ratio * rightRange);
  }

  String leftLabel(double value) => _compact(value);

  String rightLabel(double value) => _compact(leftToRight(value));

  String _compact(double value) {
    if (value.isNaN || value.isInfinite) return '--';
    if (value.abs() < 0.01) return '0';
    if (value % 1 == 0) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}
