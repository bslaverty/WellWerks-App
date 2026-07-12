import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../services/report_profile_service.dart';
import '../widgets/app_header.dart';

class ShiftReportScreen extends StatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  State<ShiftReportScreen> createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends State<ShiftReportScreen> {
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
    if (activeJob != null && shift.activeJobId != activeJob.id) {
      shift = shift.copyWith(activeJobId: activeJob.id);
      await _shiftService.saveActiveShift(shift);
    }
    final layout =
        await _layoutService.resolveProfile(shift.header.layoutProfileId);
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = activeJob;
      _layout = layout;
      _loading = false;
    });
  }

  List<ProductionReportRow> get _inventoryRows {
    if (_shift.inventory.productionRows.isNotEmpty) {
      return _shift.inventory.productionRows;
    }
    return _shift.savedRows;
  }

  List<ProductionReportRow> get _activeJobRows {
    final activeJob = _activeJob;
    final rows = activeJob == null
        ? List<ProductionReportRow>.from(_inventoryRows)
        : (_shift.activeJobId != activeJob.id
            ? <ProductionReportRow>[]
            : List<ProductionReportRow>.from(_inventoryRows));
    final order = _wellOrderSource;
    rows.sort((a, b) {
      final hourCompare = a.hourIndex.compareTo(b.hourIndex);
      if (hourCompare != 0) return hourCompare;
      final ai = order.indexOf(a.well);
      final bi = order.indexOf(b.well);
      if (ai == -1 && bi == -1) return a.well.compareTo(b.well);
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
    return rows;
  }

  List<String> get _wellOrderSource {
    final active = _activeJob;
    if (active != null && active.resolvedWellNames.isNotEmpty) {
      return active.resolvedWellNames;
    }
    return _shift.header.wells;
  }

  List<String> get _wellOrder {
    final ordered = <String>[];
    for (final well in _wellOrderSource) {
      if (!ordered.contains(well)) {
        ordered.add(well);
      }
    }
    for (final row in _activeJobRows) {
      if (!ordered.contains(row.well)) {
        ordered.add(row.well);
      }
    }
    return ordered;
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
    final rows = _activeJobRows
        .where((row) => row.well == selectedWell)
        .toList()
      ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
    return rows;
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
  }

  void _goToNextWell() {
    final wells = _wellOrder;
    if (_selectedWellIndex >= wells.length - 1) {
      return;
    }
    setState(() => _selectedWellIndex += 1);
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

    return Scaffold(
      appBar: const AppHeader(title: 'Production Report', showBack: true),
      body: ListView(
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
      ),
    );
  }
}
