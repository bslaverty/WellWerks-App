import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../services/report_profile_service.dart';
import '../widgets/app_header.dart';

class TextUpdateScreen extends StatefulWidget {
  const TextUpdateScreen({super.key});

  @override
  State<TextUpdateScreen> createState() => _TextUpdateScreenState();
}

class _TextUpdateScreenState extends State<TextUpdateScreen> {
  final _shiftService = ProductionShiftService();
  final _layoutService = ReportProfileService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  ReportLayoutProfile _layout = ReportProfileService().defaultProfile();
  bool _loading = true;
  int? _selectedHour;

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.textUpdate);
    _load();
  }

  Future<void> _load() async {
    final shift = await _shiftService.loadActiveShift();
    final activeJob = await _jobStorage.loadActiveJob();
    final layout =
        await _layoutService.resolveProfile(shift.header.layoutProfileId);
    final rows = activeJob != null && shift.activeJobId == activeJob.id
        ? shift.savedRows
        : const <ProductionReportRow>[];
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = activeJob;
      _layout = layout;
      _selectedHour = shift.selectedTextHour ??
          (rows.isEmpty ? null : rows.first.hourIndex);
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
      return 'No active job found. Start a job first, then save a Quick Round hour before using Text Update.';
    }
    return 'No saved Production Report rows for the current active job yet.\n\nGo to Quick Round, save an hour, then return here.';
  }

  String _fmt(double value) {
    final rounded = value.abs() < 0.01 ? 0 : value;
    return rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  String get _gasUnitLabel =>
      _shift.inventory.gasUnit == 'mmcfd' ? 'mmcf/d' : 'mcf/d';

  double _baseGasToDisplay(double value) {
    return _shift.inventory.gasUnit == 'mmcfd' ? value / 1000 : value;
  }

  String _gasString(String value) {
    final parsed = double.tryParse(value.trim()) ?? 0;
    return _fmt(_baseGasToDisplay(parsed));
  }

  String _fmtTimeLabel(String value) {
    final parts = value.trim().split(' ');
    if (parts.length != 2) return value.toUpperCase();
    return '${parts[0]}:00 ${parts[1].toUpperCase()}';
  }

  ProductionReportRow? get _selectedRow {
    final rows = _activeJobRows;
    if (rows.isEmpty) return null;
    final selectedHour = _selectedHour;
    if (selectedHour == null) return rows.first;
    for (final row in rows) {
      if (row.hourIndex == selectedHour) return row;
    }
    return rows.first;
  }

  String _lineFor(ProductionReportRow row, String key) {
    switch (key) {
      case 'time':
        return 'TIME - ${_fmtTimeLabel(row.time)}';
      case 'well':
        return row.well;
      case 'csg':
        return 'CSG - ${row.csg.isEmpty ? '-' : row.csg} PSI';
      case 'icp':
        return 'ICP - ${row.icp.isEmpty ? '-' : row.icp} PSI';
      case 'chk':
        return row.choke.trim().isEmpty
            ? 'CHK - -'
            : 'CHK - ${row.choke.trim()} ${row.chokeType.toLowerCase()}';
      case 'bwph':
        return 'BWPH - ${_fmt(row.waterProduction)} BBL/hr';
      case 'boph':
        return 'BOPH - ${_fmt(row.oilProduction)} BBL/hr';
      case 'gasSpotRt':
        return 'GAS SPOT RT. ${_fmt(_baseGasToDisplay(row.gas24HourRate))} $_gasUnitLabel';
      case 'diff':
        return 'DIFF - ${row.gasDifferential.isEmpty ? '-' : row.gasDifferential}"';
      case 'stat':
        return 'STAT - ${row.gasStatic.isEmpty ? '-' : row.gasStatic} PSI';
      case 'temp':
        return 'TEMP - ${row.gasTemp.isEmpty ? '-' : row.gasTemp}°';
      case 'prop':
        return 'PROP - ${row.sandRate.isEmpty ? '-' : row.sandRate} GPH';
      case 'h2oSg':
        return 'H2O SG - ${row.waterSpecificGravity.isEmpty ? '-' : row.waterSpecificGravity}';
      case 'wht':
        return 'WHT - ${row.wellheadTemp.isEmpty ? '-' : row.wellheadTemp}°';
      case 'wtrTmp':
        return 'WTR TMP - ${row.waterTemp.isEmpty ? '-' : row.waterTemp}°';
      case 'flareRt':
        return 'FLARE RT - ${row.flareRate.isEmpty ? '-' : _gasString(row.flareRate)} $_gasUnitLabel';
      case 'flarePilotTemp':
        return 'FLARE PILOT TEMP - ${row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp}°';
      case 'biocide':
        return 'BIOCIDE - ${row.biocide.isEmpty ? '-' : row.biocide} GPD';
      case 'vruGasRt':
        return 'GAS RT - ${row.vruGasRate.isEmpty ? '-' : _gasString(row.vruGasRate)} $_gasUnitLabel';
      case 'compressorInj':
        return 'COMP INJ - ${row.compressorInjection.isEmpty ? '-' : _gasString(row.compressorInjection)} $_gasUnitLabel';
      case 'vruSuction':
        return 'SUCTION - ${row.vruSuction.isEmpty ? '-' : row.vruSuction}';
      case 'vruDischarge':
        return 'DISCHARGE - ${row.vruDischarge.isEmpty ? '-' : row.vruDischarge}';
      case 'notes':
        return row.notes.isEmpty ? '-' : row.notes;
      default:
        return '';
    }
  }

  String get _preview {
    final row = _selectedRow;
    if (row == null) {
      return _emptyStateMessage;
    }

    final pad =
        _shift.header.pad.trim().isEmpty ? '-' : _shift.header.pad.trim();
    final included =
        _layout.textFields.where((field) => field.included).toList();

    final lines = <String>[];
    lines.add(pad);
    lines.add('${_fmtTimeLabel(row.time)} UPDATE');
    lines.add('');

    final vruKeys = {'vruGasRt', 'compressorInj', 'vruSuction', 'vruDischarge'};
    for (final field in included) {
      if (vruKeys.contains(field.key) || field.key == 'notes') {
        continue;
      }
      final line = _lineFor(row, field.key);
      if (line.isNotEmpty) {
        lines.add(line);
      }
    }

    final hasVru = included.any((f) => vruKeys.contains(f.key));
    if (hasVru) {
      lines.add('');
      lines.add('VRU');
      lines.add('');
      for (final field in included.where((f) => vruKeys.contains(f.key))) {
        lines.add(_lineFor(row, field.key));
      }
    }

    if (included.any((f) => f.key == 'notes')) {
      lines.add('');
      lines.add('Notes');
      lines.add(_lineFor(row, 'notes'));
    }

    return lines.join('\n');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _preview));
    final selectedHour = _selectedRow?.hourIndex;
    if (selectedHour != null) {
      _shift = _shift.copyWith(selectedTextHour: selectedHour);
      await _shiftService.saveActiveShift(_shift);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Text Update copied.')),
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

  Widget _activeJobBanner() {
    final activeJob = _activeJob;
    if (activeJob == null) {
      return _section('Active Job', const [
        Text(
          'No active job found. Start a job first to preview and copy the current Text Update safely.',
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
        appBar: AppHeader(title: 'Text Update', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selected = _selectedRow;
    return Scaffold(
      appBar: const AppHeader(title: 'Text Update', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _activeJobBanner(),
          _section('Text Update', [
            Text(
              'Layout: ${_layout.name}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: selected?.hourIndex,
              decoration: const InputDecoration(labelText: 'Select Hour'),
              items: [
                for (final row in _activeJobRows)
                  DropdownMenuItem(
                    value: row.hourIndex,
                    child: Text('${row.time} • ${row.well}'),
                  ),
              ],
              onChanged: _activeJobRows.isEmpty
                  ? null
                  : (value) async {
                      if (value == null) return;
                      setState(() => _selectedHour = value);
                      _shift = _shift.copyWith(selectedTextHour: value);
                      await _shiftService.saveActiveShift(_shift);
                    },
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  _preview,
                  style: const TextStyle(height: 1.35, fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _activeJobRows.isEmpty ? null : _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Text Update'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
