import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_service.dart';
import '../services/production_report_continuity_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../services/report_profile_service.dart';
import '../utils/production_text_update_builder.dart';
import '../widgets/app_header.dart';

class ProductionShiftChangeScreen extends StatefulWidget {
  const ProductionShiftChangeScreen({super.key});

  @override
  State<ProductionShiftChangeScreen> createState() =>
      _ProductionShiftChangeScreenState();
}

class _ProductionShiftChangeScreenState
    extends State<ProductionShiftChangeScreen> {
  final _settingsService = AppSettingsService();
  final _shiftService = ProductionShiftService();
  final _layoutService = ReportProfileService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _continuityService = const ProductionReportContinuityService();
  final _operationsLogService = OperationsLogService();
  final _previewKey = GlobalKey();

  AppSettingsData _settings = const AppSettingsData(
    defaultGasUnit: AppSettingsDefaults.gasUnit,
    defaultGaugeType: AppSettingsDefaults.gaugeType,
    defaultBblPerInch: AppSettingsDefaults.bblPerInch,
    defaultGasCalculationMethod: AppSettingsDefaults.gasCalculationMethod,
    defaultChokeDisplay: AppSettingsDefaults.chokeDisplay,
    defaultOptionalReportSections: AppSettingsDefaults.optionalReportSections,
  );
  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  ReportLayoutProfile _layout = ReportProfileService().defaultProfile();
  bool _loading = true;
  int? _selectedHour;

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.productionShiftChange);
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
    final settings = await _settingsService.load();
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    if (activeJob != null && shift.activeJobId != activeJob.id) {
      shift = shift.copyWith(activeJobId: activeJob.id);
      await _shiftService.saveActiveShift(shift);
    }
    final layout =
        await _layoutService.resolveProfile(shift.header.layoutProfileId);
    final rows = (activeJob == null || shift.activeJobId == activeJob.id)
        ? (shift.inventory.productionRows.isNotEmpty
            ? shift.inventory.productionRows
            : shift.savedRows)
        : const <ProductionReportRow>[];
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _shift = shift;
      _activeJob = activeJob;
      _layout = layout;
      _selectedHour = shift.selectedTextHour ??
          (rows.isEmpty
              ? null
              : (rows
                  .map((row) => row.hourIndex)
                  .reduce((a, b) => a > b ? a : b)));
      _loading = false;
    });
  }

  List<ProductionReportRow> get _activeJobRows {
    final normalizedRows = _continuityService.normalizedRowsForJob(
      shift: _shift,
      activeJob: _activeJob,
    );
    final activeJob = _activeJob;
    final rows = activeJob == null
        ? List<ProductionReportRow>.from(normalizedRows)
        : (_shift.activeJobId != activeJob.id
            ? <ProductionReportRow>[]
            : List<ProductionReportRow>.from(normalizedRows));
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

  List<int> get _availableHours {
    final hours = <int>{};
    for (final row in _activeJobRows) {
      hours.add(row.hourIndex);
    }
    final list = hours.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  List<ProductionReportRow> get _selectedRows {
    final rows = _activeJobRows;
    if (rows.isEmpty) return const <ProductionReportRow>[];
    final selectedHour = _selectedHour ?? _availableHours.last;
    return rows.where((row) => row.hourIndex == selectedHour).toList();
  }

  List<ProductionReportRow> get _orderedSelectedRows {
    final rows = List<ProductionReportRow>.from(_selectedRows);
    final order = _wellOrderSource;
    rows.sort((a, b) {
      final ai = order.indexOf(a.well);
      final bi = order.indexOf(b.well);
      if (ai == -1 && bi == -1) return a.well.compareTo(b.well);
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
    return rows;
  }

  ProductionReportRow? get _selectedRow {
    final rows = _selectedRows;
    if (rows.isEmpty) return null;
    return rows.first;
  }

  String get _emptyStateMessage {
    if (_activeJob == null && _shift.activeJobId.trim().isEmpty) {
      return 'No active job found. Start a job first, then save a Quick Round hour before using Production Shift Change.';
    }
    return 'No saved Quick Round hours for the current active job yet. Save a Quick Round hour first.';
  }

  String _fmtTimeLabel(String value) {
    final upper = value.trim().toUpperCase();
    if (upper.isEmpty) return 'Selected';
    return upper;
  }

  String _shiftLabel() {
    final shift = _activeJob?.shift.trim() ?? '';
    if (shift.isEmpty) return '';
    return shift.toLowerCase().endsWith('shift') ? shift : '$shift Shift';
  }

  List<String> _shiftChangeHeaderLines() {
    final row = _selectedRow;
    final company = (_activeJob?.company ?? _shift.header.company).trim();
    final pad = (_activeJob?.padName ?? _shift.header.pad).trim();
    final lines = <String>[
      '${_fmtTimeLabel(row?.time ?? '')} Production Shift Change',
    ];
    if (company.isNotEmpty) lines.add(company);
    if (pad.isNotEmpty) lines.add(pad);
    final shift = _shiftLabel();
    if (shift.isNotEmpty) lines.add(shift);
    return lines;
  }

  String _bbl(double value) {
    if (value % 1 == 0) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  List<String> _gaugeLinesFor(ProductionReportRow row) {
    final lines = <String>[];
    for (final source in [row.waterGaugeText, row.oilGaugeText]) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) continue;
      for (final part in trimmed.split(',')) {
        final next = part.trim();
        if (next.isNotEmpty) {
          lines.add(next);
        }
      }
    }
    return lines;
  }

  String get _preview {
    final rows = _orderedSelectedRows;
    if (rows.isEmpty) return _emptyStateMessage;

    final basePreview = ProductionTextUpdateBuilder(
      settings: _settings,
      shift: _shift,
      activeJob: _activeJob,
      layout: _layout,
      orderedRows: rows,
      headerLines: _shiftChangeHeaderLines(),
    ).buildPreview();

    final lines = <String>[basePreview, ''];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (rows.length > 1) {
        lines.add(row.well.trim().isEmpty ? 'Well' : row.well.trim());
        lines.add('');
      }

      final gaugeLines = _gaugeLinesFor(row);
      if (gaugeLines.isNotEmpty) {
        lines.add('Tank Gauges');
        lines.addAll(gaugeLines);
        lines.add('');
      }

      lines.add('Hauled / Pumped');
      lines.add('Water Hauled - ${_bbl(row.waterHauled)} BBL');
      lines.add('Water Pumped - ${_bbl(row.waterPumped)} BBL');
      lines.add('Oil Hauled - ${_bbl(row.oilHauled)} BBL');
      lines.add('Oil Pumped - ${_bbl(row.oilPumped)} BBL');

      if (i != rows.length - 1) {
        lines.add('');
      }
    }
    return lines.join('\n').trim();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _preview));
    final selectedHour = _selectedRow?.hourIndex;
    if (selectedHour != null) {
      _shift = _shift.copyWith(selectedTextHour: selectedHour);
      await _shiftService.saveActiveShift(_shift);
    }
    await _logShiftChangeEvent(trigger: 'copy');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Production Shift Change copied.')),
    );
  }

  Future<void> _previewScroll() async {
    final context = _previewKey.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 200),
    );
    await _logShiftChangeEvent(trigger: 'preview');
  }

  OperationsLogWorkflow _operationsWorkflowForActiveJob() {
    final workflow = (_activeJob?.workflow ?? '').trim().toLowerCase();
    if (workflow == OperationsLogWorkflow.cleanout.name) {
      return OperationsLogWorkflow.cleanout;
    }
    return OperationsLogWorkflow.drillout;
  }

  Future<void> _logShiftChangeEvent({required String trigger}) async {
    final activeJob = _activeJob;
    if (activeJob == null) return;
    final rows = _orderedSelectedRows;
    if (rows.isEmpty) return;

    final firstWell = rows.first.well.trim();
    final matchedWell = activeJob.resolvedWellEntries.where((entry) {
      return entry.name.trim().toLowerCase() == firstWell.toLowerCase();
    }).toList();
    final selectedWellId = matchedWell.isEmpty
        ? (activeJob.wellIds.isEmpty ? '' : activeJob.wellIds.first)
        : matchedWell.first.id;

    try {
      await _operationsLogService.appendEventEntry(
        workflow: _operationsWorkflowForActiveJob(),
        jobId: activeJob.id,
        wellId: selectedWellId,
        wellName: firstWell.isEmpty ? activeJob.primaryWell : firstWell,
        entryType: 'shiftChange',
        timestamp: DateTime.now(),
        generatedText: _preview,
        structuredData: <String, dynamic>{
          'source': 'productionShiftChangeScreen',
          'trigger': trigger,
          'selectedHour': _selectedHour,
          'wellCount': rows.length,
          'rows': rows
              .map(
                (row) => <String, dynamic>{
                  'well': row.well,
                  'time': row.time,
                  'waterHauled': row.waterHauled,
                  'oilHauled': row.oilHauled,
                  'choke': row.choke,
                },
              )
              .toList(growable: false),
        },
        notes:
            'Production Shift Change generated from ${trigger.toLowerCase()}.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[ProductionShiftChange] Failed to append Operations Log entry: $error\n$stackTrace',
      );
    }
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
            'Shift: Active shift data',
            style: TextStyle(color: Colors.white70),
          ),
        ]);
      }
      return _section('Active Job', const [
        Text(
          'No active job found. Start a job first to preview and copy the current Production Shift Change safely.',
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
          _jobChip(
            activeJob.isMultiWellJob ? 'Wells' : 'Well',
            activeJob.isMultiWellJob
                ? activeJob.resolvedWellNames.join(', ')
                : activeJob.primaryWell,
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
        border: Border.all(
          color: const Color(0xFFCDA56A).withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        '$label: ${value.trim().isEmpty ? 'Not entered' : value.trim()}',
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Production Shift Change', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selected = _selectedRow;
    return Scaffold(
      appBar: const AppHeader(title: 'Production Shift Change', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _activeJobBanner(),
          _section('Production Shift Change', [
            Text(
              'Layout: ${_layout.name}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: selected?.hourIndex,
              decoration: const InputDecoration(labelText: 'Select Hour'),
              items: [
                for (final hour in _availableHours)
                  DropdownMenuItem(
                    value: hour,
                    child: Text(_activeJobRows
                        .firstWhere((row) => row.hourIndex == hour)
                        .time),
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
            if (_orderedSelectedRows.length > 1)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Multi-well mode: this shift change includes all wells saved for the selected hour.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(height: 10),
            Card(
              key: _previewKey,
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
              child: OutlinedButton.icon(
                onPressed: _activeJobRows.isEmpty ? null : _previewScroll,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Preview Shift Change'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _activeJobRows.isEmpty ? null : _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Shift Change'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
