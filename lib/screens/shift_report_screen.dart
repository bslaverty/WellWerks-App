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

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.productionReport);
    _load();
  }

  Future<void> _load() async {
    final shift = await _shiftService.loadActiveShift();
    final activeJob = await _jobStorage.loadActiveJob();
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

  List<ProductionReportRow> get _activeJobRows {
    final activeJob = _activeJob;
    if (activeJob == null) {
      return const [];
    }
    if (_shift.activeJobId != activeJob.id) {
      return const [];
    }
    return _shift.savedRows;
  }

  bool get _hasActiveJob => _activeJob != null;

  String get _emptyStateMessage {
    if (!_hasActiveJob) {
      return 'No active job found. Start a job first, then save Quick Round hours to view a Production Report.';
    }
    return 'No saved Production Report rows for the current active job yet. Save hours in Quick Round first.';
  }

  String _fmt(double value) {
    final rounded = value.abs() < 0.01 ? 0 : value;
    return rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  double _baseGasToDisplay(double value) {
    return _shift.inventory.gasUnit == 'mmcfd' ? value / 1000 : value;
  }

  String _gasString(String value) {
    final parsed = double.tryParse(value.trim()) ?? 0;
    return _fmt(_baseGasToDisplay(parsed));
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
      case 'csg':
        return row.csg;
      case 'icp':
        return row.icp;
      case 'chk':
        return _chk(row);
      case 'bwph':
        return _fmt(row.waterProduction);
      case 'boph':
        return _fmt(row.oilProduction);
      case 'gasSpotRt':
        return _fmt(_baseGasToDisplay(row.gas24HourRate));
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
      case 'biocide':
        return row.biocide;
      case 'vruGasRt':
        return _gasString(row.vruGasRate);
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
        lines.add(
            '${_headerLabel(key)}: ${_valueFor(row, key).isEmpty ? '-' : _valueFor(row, key)}');
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
    final rows = _activeJobRows;
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

  Widget _activeJobBanner() {
    final activeJob = _activeJob;
    if (activeJob == null) {
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
                        ? activeJob.wells.join(', ')
                        : activeJob.primaryWell),
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
            child: FilledButton.icon(
              onPressed: _activeJobRows.isEmpty ? null : _copyReport,
              icon: const Icon(Icons.copy_all),
              label: const Text('Copy Production Report'),
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
