import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../services/report_profile_service.dart';
import '../utils/choke_parsing.dart';
import '../widgets/app_header.dart';

class ShiftReportScreen extends StatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  State<ShiftReportScreen> createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends State<ShiftReportScreen> {
  static const _chartPrefsBase = 'wellwerks_production_report_chart_v1';

  final _shiftService = ProductionShiftService();
  final _layoutService = ReportProfileService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _profileDefaults = JobProfileDefaultsService();

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  ReportLayoutProfile _layout = ReportProfileService().defaultProfile();
  bool _loading = true;
  int _selectedWellIndex = 0;
  Map<_ChartSeries, bool> _seriesVisibility = _defaultSeriesVisibility();
  String _pointDetail = '';
  _ChartSeries? _pointDetailSeries;

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

    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = activeJob;
      _layout = layout;
      _selectedWellIndex = selectedWellIndex;
      _seriesVisibility = _resolvedSeriesVisibility(
        savedPrefs['visibleSeries'] as List<dynamic>?,
      );
      _loading = false;
    });
  }

  String _chartPrefsKeyFor(JobSetup? activeJob, ProductionShift shift) {
    final id = (activeJob?.id ?? shift.activeJobId).trim();
    if (id.isEmpty) return _chartPrefsBase;
    return '$_chartPrefsBase:$id';
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
    final inventoryRows = shift.inventory.productionRows.isNotEmpty
        ? shift.inventory.productionRows
        : shift.savedRows;
    final rows = activeJob == null
        ? List<ProductionReportRow>.from(inventoryRows)
        : (shift.activeJobId != activeJob.id
            ? <ProductionReportRow>[]
            : List<ProductionReportRow>.from(inventoryRows));

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

  double? _startingGasBaseline() {
    if (!_shift.inventory.useStartingReadings) {
      return null;
    }
    final text = _shift.inventory.startingGasAccum.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null) return null;
    return value >= 0 ? value : null;
  }

  String _gasSpotForRow(ProductionReportRow row) {
    final current = row.currentGasAccum;
    if (current.isNaN || current < 0) return '--';
    final previous = _previousRowForWell(
      row,
      (item) => !item.currentGasAccum.isNaN && item.currentGasAccum > 0,
    );
    final baseline = previous?.currentGasAccum ?? _startingGasBaseline();
    if (baseline == null) return '--';
    final delta = current - baseline;
    if (delta < 0) return '--';
    return _fmt(_baseGasToDisplay(delta));
  }

  String _chk(ProductionReportRow row) {
    final value = row.choke.trim();
    if (value.isEmpty) return '-';
    return '$value ${row.chokeType}';
  }

  List<ReportField> get _visibleColumns =>
      _layout.reportFields.where((field) => field.included).toList();

  List<String> get _visibleFieldKeys {
    final activeJob = _activeJob;
    if (activeJob != null && activeJob.wellFieldKeys.isNotEmpty) {
      return List<String>.from(activeJob.wellFieldKeys);
    }
    return _visibleColumns.map((field) => field.key).toList();
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
      case 'gasSpotRt':
        return 'GAS SPOT RT.';
      case 'diff':
        return 'DIFF';
      case 'stat':
        return 'STAT';
      case 'temp':
        return 'TEMP';
      case 'prop':
        return 'PROP';
      case 'wht':
        return 'WHT';
      case 'wtrTmp':
        return 'WTR TMP';
      case 'flareRt':
        return 'FLARE RT';
      case 'flarePilotTemp':
        return 'FLARE PILOT TEMP';
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
      case 'prop':
        return row.sandRate;
      case 'h2oSg':
        return row.waterSpecificGravity;
      case 'wht':
        return row.wellheadTemp;
      case 'wtrTmp':
        return row.waterTemp;
      case 'flareRt':
        return _gasString(row.flareRate);
      case 'flarePilotTemp':
        return row.flarePilotTemp;
      case 'riserTemp':
        return row.wellheadTemp;
      case 'riserPl':
        return '-';
      case 'clrFlarePilot':
        return row.flarePilotTemp;
      case 'clrFlareRt':
        return _gasString(row.flareRate);
      case 'clrFlareTemp':
        return row.gasTemp;
      case 'biocide':
        return row.biocide;
      case 'scavenger':
        return row.scavenger;
      case 'defoamer':
        return row.defoamer;
      case 'scaleInhibitor':
        return row.scaleInhibitor;
      case 'vruGasRt':
        return _gasString(row.vruGasRate);
      case 'vruSuct':
        return row.vruSuction;
      case 'vruDisc':
        return row.vruDischarge;
      case 'compressorInj':
        return _gasString(row.compressorInjection);
      case 'vruSuction':
        return row.vruSuction;
      case 'vruDischarge':
        return row.vruDischarge;
      case 'notes':
        return row.notes;
      default:
        return '';
    }
  }

  String get _reportText {
    final rows = _activeJobRows;
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
      for (final row in _activeJobRows)
        _visibleFieldKeys.map((key) => _valueFor(row, key)).toList(),
    ];

    return csvRows
        .map((row) =>
            row.map((value) => '"${value.replaceAll('"', '""')}"').join(','))
        .join('\n');
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _reportText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Production Report copied.')),
    );
  }

  Future<void> _previewReport() async {
    final text = _reportText;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview Text'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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

  Widget _buildTable() {
    final rows = _rowsForSelectedWell;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _emptyStateMessage,
          style: const TextStyle(color: Colors.white70),
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final key in _visibleFieldKeys) _column(_headerLabel(key))
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final key in _visibleFieldKeys) _cell(_valueFor(row, key)),
              ],
            ),
        ],
      ),
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
                  'Saved hours: ${_activeJobRows.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _buildTable(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _activeJobRows.isEmpty ? null : _previewReport,
            icon: const Icon(Icons.preview_outlined),
            label: const Text('Preview Text'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _activeJobRows.isEmpty ? null : _copyReport,
            icon: const Icon(Icons.copy_all),
            label: const Text('Copy Text'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _activeJobRows.isEmpty ? null : _exportReport,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Export Production Report'),
          ),
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFCDA56A).withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        '$label: ${value.trim().isEmpty ? 'Not entered' : value.trim()}',
        style:
            const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
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
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
