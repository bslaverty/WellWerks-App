import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/job_setup.dart';
import '../models/operations_log_entry.dart';
import '../models/production_shift.dart';
import '../services/job_storage_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/operations_log_service.dart';
import '../services/production_report_continuity_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../services/report_profile_service.dart';
import '../services/wellwerks_qr_transfer_service.dart';
import '../utils/flywheel_text_update_formatter.dart';
import '../widgets/app_header.dart';
import '../widgets/sts_date_time_selector_sheet.dart';

enum _EntryTimeMode {
  currentTime,
  manualTime,
}

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
  final _profileDefaults = JobProfileDefaultsService();
  final _continuityService = const ProductionReportContinuityService();
  final _operationsLogService = OperationsLogService();
  final _qrTransferService = const WellWerksQrTransferService();

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  ReportLayoutProfile _layout = ReportProfileService().defaultProfile();
  bool _loading = true;
  int? _selectedHour;
  _EntryTimeMode _entryTimeMode = _EntryTimeMode.currentTime;
  DateTime? _manualEntryTime;
  String _lastFinalizeLogKey = '';

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.textUpdate);
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
    final rows = (activeJob == null || shift.activeJobId == activeJob.id)
        ? (shift.inventory.productionRows.isNotEmpty
            ? shift.inventory.productionRows
            : shift.savedRows)
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

  bool get _hasActiveJob =>
      _activeJob != null ||
      _shift.activeJobId.trim().isNotEmpty ||
      _activeJobRows.isNotEmpty;

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

  String _wholeFmt(double value) {
    if (value.isNaN) return '--';
    if (value < 0) return '--';
    return value.round().toStringAsFixed(0);
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

  bool get _showEcdSection => _equipmentSectionSelected('FLARE / ECD');

  bool get _showFlareEcdSection => _showFlareSection || _showEcdSection;

  bool get _flareEcdGasRateEnabled {
    final setup = _activeJob?.drilloutSetup;
    final raw = setup?['flareEcdGasRateEnabled'];
    if (raw is bool) return raw;
    return true;
  }

  bool get _notesSectionEnabled {
    final setup = _activeJob?.drilloutSetup;
    final raw = setup?['includeNotesSection'];
    if (raw is bool) return raw;
    return true;
  }

  bool _chemicalSelected(String name) {
    final selected = _activeJob?.selectedChemicals ?? const <String>[];
    return selected.any((item) => item.toLowerCase() == name.toLowerCase());
  }

  String _biocideValue(ProductionReportRow row) {
    if (!_chemicalSelected('Biocide')) {
      return 'N/A';
    }
    return row.biocide.isEmpty ? '-' : row.biocide;
  }

  String get _headerCompanyName {
    final activeJob = _activeJob;
    if (activeJob != null && activeJob.company.trim().isNotEmpty) {
      return activeJob.company.trim();
    }
    return _shift.header.company.trim();
  }

  String get _headerPadName {
    final activeJob = _activeJob;
    if (activeJob != null && activeJob.padName.trim().isNotEmpty) {
      return activeJob.padName.trim();
    }
    return _shift.header.pad.trim();
  }

  List<String> get _headerWellList {
    final activeJob = _activeJob;
    final wells = <String>[];
    final source = activeJob?.resolvedWellNames.isNotEmpty == true
        ? activeJob!.resolvedWellNames
        : _shift.header.wells;
    for (final well in source) {
      final trimmed = well.trim();
      if (trimmed.isNotEmpty && !wells.contains(trimmed)) {
        wells.add(trimmed);
      }
    }
    return wells;
  }

  String get _headerWellListText =>
      _headerWellList.isEmpty ? '-' : _headerWellList.join(' / ');

  String get _headerUpdateTime {
    final entryTime = _entryTimeMode == _EntryTimeMode.currentTime
        ? DateTime.now()
        : (_manualEntryTime ?? DateTime.now());
    final time = TimeOfDay.fromDateTime(entryTime).format(context);
    return '$time UPDATE';
  }

  List<String> _buildHeaderLines() {
    final lines = <String>[];
    final company = _headerCompanyName;
    final pad = _headerPadName;
    if (company.isNotEmpty) {
      lines.add(company);
    }
    if (pad.isNotEmpty) {
      lines.add(pad);
    }
    if (_headerWellListText != '-') {
      lines.add(_headerWellListText);
    }
    lines.add(_headerUpdateTime);
    return lines;
  }

  ProductionReportRow? get _selectedRow {
    final rows = _selectedRows;
    if (rows.isEmpty) return null;
    return rows.first;
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
    final selectedHour = _selectedHour ?? rows.first.hourIndex;
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

  String _lineFor(ProductionReportRow row, String key) {
    const vruKeys = {'vruGasRt', 'compressorInj', 'vruSuction', 'vruDischarge'};
    const flareKeys = {
      'flareRt',
      'flarePilotTemp',
      'flareEcdGasRate',
      'flareEcdTemp',
    };
    if (!_showVruSection && vruKeys.contains(key)) {
      return '';
    }
    if (!_showFlareSection && flareKeys.contains(key)) {
      return '';
    }
    switch (key) {
      case 'well':
        return row.well;
      case 'wellName':
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
        return 'BWPH - ${_wholeFmt(row.waterProduction)} BBL/hr';
      case 'boph':
        return 'BOPH - ${_wholeFmt(row.oilProduction)} BBL/hr';
      case 'gasSpotRt':
        return 'GAS RATE ${_fmt(_baseGasToDisplay(row.gas24HourRate))} $_gasUnitLabel';
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
      case 'flareEcdTemp':
        return 'FLARE / ECD TEMP - ${row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp}°F';
      case 'flareEcdGasRate':
        if (!_flareEcdGasRateEnabled) return '';
        return 'FLARE / ECD GAS RATE - ${row.flareRate.isEmpty ? '-' : _gasString(row.flareRate)} $_gasUnitLabel';
      case 'biocide':
        final value = _biocideValue(row);
        return value == 'N/A' ? 'BIOCIDE - N/A' : 'BIOCIDE - $value GPD';
      case 'vruGasRt':
        return 'GAS RT - ${row.vruGasRate.isEmpty ? '-' : _gasString(row.vruGasRate)} $_gasUnitLabel';
      case 'vruSuct':
        return 'SUCT - ${row.vruSuction.isEmpty ? '-' : row.vruSuction}';
      case 'vruDisc':
        return 'DISC - ${row.vruDischarge.isEmpty ? '-' : row.vruDischarge}';
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

  String _valueForProfileField(ProductionReportRow row, String key) {
    if (!_showVruSection &&
        const {
          'vruGasRt',
          'vruSuct',
          'vruDisc',
          'compressorInj',
          'vruSuction',
          'vruDischarge'
        }.contains(key)) {
      return '';
    }
    if (!_showFlareSection &&
        const {'flareRt', 'flarePilotTemp', 'flareEcdGasRate', 'flareEcdTemp'}
            .contains(key)) {
      return '';
    }
    switch (key) {
      case 'wellName':
        return row.well.isEmpty ? '-' : row.well;
      case 'csg':
        return row.csg.isEmpty ? '-' : row.csg;
      case 'icp':
        return row.icp.isEmpty ? '-' : row.icp;
      case 'chk':
        return row.choke.trim().isEmpty
            ? '-'
            : '${row.choke.trim()} ${row.chokeType.toUpperCase()}';
      case 'bwph':
        return _wholeFmt(row.waterProduction);
      case 'boph':
        return _wholeFmt(row.oilProduction);
      case 'gasSpotRt':
        return '${_fmt(_baseGasToDisplay(row.gas24HourRate))} $_gasUnitLabel';
      case 'stat':
        return row.gasStatic.isEmpty ? '-' : row.gasStatic;
      case 'diff':
        return row.gasDifferential.isEmpty ? '-' : row.gasDifferential;
      case 'temp':
        return row.gasTemp.isEmpty ? '-' : row.gasTemp;
      case 'prop':
        return row.sandRate.isEmpty ? '-' : row.sandRate;
      case 'wht':
        return row.wellheadTemp.isEmpty ? '-' : row.wellheadTemp;
      case 'flareEcdTemp':
        return row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp;
      case 'flareEcdGasRate':
        if (!_flareEcdGasRateEnabled) return '';
        return '${_gasString(row.flareRate)} $_gasUnitLabel';
      case 'biocide':
        return _biocideValue(row);
      case 'vruGasRt':
        return row.vruGasRate.isEmpty
            ? '-'
            : '${_gasString(row.vruGasRate)} $_gasUnitLabel';
      case 'vruSuct':
        return row.vruSuction.isEmpty ? '-' : row.vruSuction;
      case 'vruDisc':
        return row.vruDischarge.isEmpty ? '-' : row.vruDischarge;
      default:
        return '-';
    }
  }

  String _machTextPreview(JobSetup activeJob, List<ProductionReportRow> rows) {
    final lines = _buildHeaderLines();
    lines.add('');
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      lines.add(row.well.trim().isEmpty ? 'Well' : row.well.trim());
      lines.add('CHK: ${_valueForProfileField(row, 'chk')}');
      lines.add('CSG: ${_valueForProfileField(row, 'csg')}');
      lines.add('WTR: ${_valueForProfileField(row, 'bwph')}');
      lines.add('OIL: ${_valueForProfileField(row, 'boph')}');
      lines.add('GAS: ${_valueForProfileField(row, 'gasSpotRt')}');
      lines.add('SAND: ${_valueForProfileField(row, 'prop')}');
      if ((activeJob.activeEquipmentSections.contains('FLARE / ECD')) &&
          _showFlareEcdSection) {
        lines.add('');
        lines.add('FLARE / ECD');
        lines.add(
            'Temperature: ${row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp} °F');
        if (_flareEcdGasRateEnabled) {
          lines.add(
              'Gas Rate: ${row.flareRate.isEmpty ? '-' : _gasString(row.flareRate)} $_gasUnitLabel');
        }
      }
      if (i != rows.length - 1) {
        lines.add('');
      }
    }
    return lines.join('\n');
  }

  String _flywheelUpdateLine(DateTime value) {
    final local = value.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final marker = local.hour >= 12 ? 'pm' : 'am';
    return '$hour12:$minute$marker update';
  }

  String _flywheelMcf(ProductionReportRow row) {
    final value = _baseGasToDisplay(row.gas24HourRate);
    if (value.isNaN || value.isInfinite) return '-';
    return value.round().toString();
  }

  String _flywheelChoke(ProductionReportRow row) {
    final raw = row.choke.trim();
    return raw.isEmpty ? '-' : raw;
  }

  String _flywheelTextPreview(
    List<ProductionReportRow> rows, {
    required DateTime entryTime,
  }) {
    final updateLine = _flywheelUpdateLine(entryTime);
    final locationLine = _headerPadName;

    final wellBlocks = rows
        .map(
          (row) => FlywheelWellLineData(
            wellName: row.well,
            tubing: row.tbg,
            csg: row.csg,
            choke: _flywheelChoke(row),
            oil: _wholeFmt(row.oilProduction),
            water: _wholeFmt(row.waterProduction),
            diff: row.gasDifferential,
            stat: row.gasStatic,
            temp: row.gasTemp,
            mcf: _flywheelMcf(row),
            sand: row.sandRate,
          ),
        )
        .toList();

    return buildFlywheelTextUpdate(
      updateLine: updateLine,
      locationLine: locationLine,
      wells: wellBlocks,
    );
  }

  String _continentalTextPreview(
    JobSetup activeJob,
    List<ProductionReportRow> rows,
  ) {
    final defaults = _profileDefaults.profileForCompany(activeJob.company);
    final activeSections = activeJob.activeEquipmentSections.isEmpty
        ? defaults.defaultActiveSections
        : activeJob.activeEquipmentSections;

    final lines = _buildHeaderLines();
    lines.add('');

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (activeJob.isMultiWellJob) {
        lines.add(row.well.trim().isEmpty ? 'Well' : row.well.trim());
      }
      for (final key in defaults.wellFieldKeys) {
        final label = defaults.textLabels[key] ?? key.toUpperCase();
        lines.add('$label: ${_valueForProfileField(row, key)}');
      }

      if (activeSections.contains('FLARE / ECD') && _showFlareEcdSection) {
        lines.add('');
        lines.add('FLARE / ECD');
        lines.add(
            'Temperature: ${row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp} °F');
        if (_flareEcdGasRateEnabled) {
          lines.add(
              'Gas Rate: ${row.flareRate.isEmpty ? '-' : _gasString(row.flareRate)} $_gasUnitLabel');
        }
      }

      if (activeSections.contains('VRU') && _showVruSection) {
        lines.add('');
        lines.add('VRU');
        lines.add(
            'GAS RT: ${row.vruGasRate.isEmpty ? '-' : _gasString(row.vruGasRate)} $_gasUnitLabel');
        lines.add('SUCT: ${row.vruSuction.isEmpty ? '-' : row.vruSuction}');
        lines.add('DISC: ${row.vruDischarge.isEmpty ? '-' : row.vruDischarge}');
      }

      if (_notesSectionEnabled) {
        lines.add('');
        lines.add('Notes');
        lines.add(row.notes.isEmpty ? '-' : row.notes);
      }

      if (i != rows.length - 1) {
        lines.add('');
      }
    }

    return lines.join('\n');
  }

  String get _preview {
    if (_orderedSelectedRows.isEmpty) {
      return _emptyStateMessage;
    }

    final activeJob = _activeJob;
    final selectedCompany = _profileDefaults.normalizeCompany(
      activeJob?.company ?? _shift.header.company,
    );
    if (activeJob != null) {
      final previewRows = _orderedSelectedRows;
      final company = _profileDefaults.normalizeCompany(activeJob.company);
      if (company == JobProfileDefaultsService.companyMach) {
        return _machTextPreview(activeJob, previewRows);
      }
      if (company == JobProfileDefaultsService.companyContinental) {
        return _continentalTextPreview(activeJob, previewRows);
      }
      if (company == JobProfileDefaultsService.companyFlywheel) {
        return _flywheelTextPreview(
          previewRows,
          entryTime: _selectedEntryTime(),
        );
      }
    }

    if (selectedCompany == JobProfileDefaultsService.companyFlywheel) {
      return _flywheelTextPreview(
        _orderedSelectedRows,
        entryTime: _selectedEntryTime(),
      );
    }

    final previewRows = _orderedSelectedRows;
    final included =
        _layout.textFields.where((field) => field.included).toList();

    final lines = _buildHeaderLines();
    lines.add('');

    final vruKeys = {'vruGasRt', 'compressorInj', 'vruSuction', 'vruDischarge'};
    for (var i = 0; i < previewRows.length; i++) {
      final previewRow = previewRows[i];
      lines.add(
          previewRow.well.trim().isEmpty ? 'Well' : previewRow.well.trim());
      for (final field in included) {
        if (field.key == 'time' ||
            vruKeys.contains(field.key) ||
            field.key == 'notes') {
          continue;
        }
        final line = _lineFor(previewRow, field.key);
        if (line.isNotEmpty) {
          lines.add(line);
        }
      }

      final hasVru =
          _showVruSection && included.any((f) => vruKeys.contains(f.key));
      if (hasVru) {
        lines.add('');
        lines.add('VRU');
        lines.add('');
        for (final field in included.where((f) => vruKeys.contains(f.key))) {
          lines.add(_lineFor(previewRow, field.key));
        }
      }

      if (_showEcdSection) {
        lines.add('');
        lines.add('ECD');
        lines.add('STATUS - ON/OFF');
        lines.add('TEMP - --');
      }

      if (included.any((f) => f.key == 'notes')) {
        lines.add('');
        lines.add('Notes');
        lines.add(_lineFor(previewRow, 'notes'));
      }

      if (i != previewRows.length - 1) {
        lines.add('');
      }
    }

    return lines.join('\n');
  }

  String _entryTimeModeLabel() {
    if (_entryTimeMode == _EntryTimeMode.currentTime) {
      return 'Current Time';
    }
    return 'Manual Time';
  }

  DateTime _selectedEntryTime() {
    if (_entryTimeMode == _EntryTimeMode.currentTime) {
      return DateTime.now();
    }
    return _manualEntryTime ?? DateTime.now();
  }

  Future<void> _pickManualEntryTime() async {
    final base = _manualEntryTime ?? DateTime.now();
    final selection = await showStsDateTimeSelectorSheet(
      context,
      title: 'Entry Time',
      helperText: 'Choose the operational time for this Text Update.',
      readingTimestamp: base,
      initialValue: base,
    );
    if (!mounted || selection == null || selection.cleared) return;
    if (selection.value == null) return;
    setState(() {
      _manualEntryTime = selection.value;
    });
  }

  String _entryTimeDisplay() {
    final value = _selectedEntryTime();
    final date = MaterialLocalizations.of(context).formatCompactDate(value);
    final time = TimeOfDay.fromDateTime(value).format(context);
    return '$date $time';
  }

  String _finalizeLogKey({
    required String shareMethod,
    required DateTime entryTime,
    required String text,
  }) {
    final jobId = _activeJob?.id ?? '';
    return '$jobId|$shareMethod|${entryTime.toIso8601String()}|${_selectedHour ?? -1}|${text.hashCode}';
  }

  Future<OperationsLogEntry?> _logTextUpdateEvent({
    required String shareMethod,
    required DateTime entryTime,
  }) async {
    final activeJob = _activeJob;
    if (activeJob == null) return null;
    final rows = _orderedSelectedRows;
    if (rows.isEmpty) return null;

    final generatedText = _preview;
    final dedupeKey = _finalizeLogKey(
      shareMethod: shareMethod,
      entryTime: entryTime,
      text: generatedText,
    );
    if (_lastFinalizeLogKey == dedupeKey) {
      return null;
    }

    final firstWell = rows.first.well.trim();
    final matchedWell = activeJob.resolvedWellEntries.where((entry) {
      return entry.name.trim().toLowerCase() == firstWell.toLowerCase();
    }).toList();
    final selectedWellId = matchedWell.isEmpty
        ? (activeJob.wellIds.isEmpty ? '' : activeJob.wellIds.first)
        : matchedWell.first.id;

    try {
      final entry = await _operationsLogService.createLocalEntry(
        workflow: _operationsWorkflowForActiveJob(),
        jobId: activeJob.id,
        wellId: selectedWellId,
        wellName: firstWell.isEmpty ? activeJob.primaryWell : firstWell,
        readingTimestamp: entryTime,
        entryType: 'textUpdate',
        generatedText: generatedText,
        structuredData: <String, dynamic>{
          'source': 'textUpdateScreen',
          'sharedVia': shareMethod,
          'entryTime': entryTime.toIso8601String(),
          'loggedAt': DateTime.now().toIso8601String(),
          'selectedHour': _selectedHour,
          'wellCount': rows.length,
          'rows': rows
              .map(
                (row) => <String, dynamic>{
                  'well': row.well,
                  'time': row.time,
                  'casingPressure': row.csg,
                  'choke': row.choke,
                  'gasRate': row.gas24HourRate,
                  'waterHauled': row.waterHauled,
                  'oilHauled': row.oilHauled,
                },
              )
              .toList(growable: false),
        },
        notes:
            'Text Update finalized via $shareMethod from Production workflow.',
      );
      await _operationsLogService.upsertEntry(
        workflow: _operationsWorkflowForActiveJob(),
        jobId: activeJob.id,
        entry: entry,
      );
      _lastFinalizeLogKey = dedupeKey;
      return entry;
    } catch (error, stackTrace) {
      debugPrint(
        '[TextUpdate] Failed to append Operations Log entry: $error\n$stackTrace',
      );
      return null;
    }
  }

  Future<void> _copyTextFinalize() async {
    final entryTime = _selectedEntryTime();
    final text = _preview;
    await Clipboard.setData(ClipboardData(text: text));
    final selectedHour = _selectedRow?.hourIndex;
    if (selectedHour != null) {
      _shift = _shift.copyWith(selectedTextHour: selectedHour);
      await _shiftService.saveActiveShift(_shift);
    }
    await _logTextUpdateEvent(
      shareMethod: 'copyText',
      entryTime: entryTime,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Text copied and logged.')),
    );
  }

  OperationsLogWorkflow _operationsWorkflowForActiveJob() {
    final workflow = (_activeJob?.workflow ?? '').trim().toLowerCase();
    if (workflow == OperationsLogWorkflow.cleanout.name) {
      return OperationsLogWorkflow.cleanout;
    }
    return OperationsLogWorkflow.drillout;
  }

  Future<void> _messageFinalize() async {
    final entryTime = _selectedEntryTime();
    final text = _preview;
    final smsUri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    var launched = false;
    if (await canLaunchUrl(smsUri)) {
      launched = await launchUrl(smsUri);
    }
    if (!launched) {
      await Share.share(text, subject: 'WellWerks Text Update');
      launched = true;
    }
    if (!launched) return;
    await _logTextUpdateEvent(
      shareMethod: 'message',
      entryTime: entryTime,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message opened and logged.')),
    );
  }

  Future<void> _showShareQrDialog(String qrValue) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: qrValue,
              version: QrVersions.auto,
              size: 280,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 10),
            const Text(
              'Scan this QR nearby or tap Share QR to send it as an image.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _qrTransferService.shareQrPng(
                  qrValue: qrValue,
                  fileName: 'text_update_qr',
                  shareContext: dialogContext,
                  subject: 'WellWerks Text Update QR',
                );
              } catch (error, stackTrace) {
                debugPrint(
                  '[TextUpdate] Failed to share QR image: $error\n$stackTrace',
                );
              }
            },
            child: const Text('Share QR'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareQrFinalize() async {
    final activeJob = _activeJob;
    if (activeJob == null) return;
    final entryTime = _selectedEntryTime();
    final entry = await _logTextUpdateEvent(
      shareMethod: 'qr',
      entryTime: entryTime,
    );
    if (entry == null) return;

    final packageType =
        _operationsWorkflowForActiveJob() == OperationsLogWorkflow.cleanout
            ? OperationsLogPackageType.cleanoutReading
            : OperationsLogPackageType.drilloutReading;
    final package = await _operationsLogService.buildPackage(
      packageType: packageType,
      persistentJobId: activeJob.id,
      entries: [entry],
    );
    final encoded = _operationsLogService.encodePackage(package);
    if (!mounted) return;
    await _showShareQrDialog(encoded);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR shared and logged.')),
    );
  }

  Future<void> _openPreviewActions() async {
    if (_activeJobRows.isEmpty) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Text Update Preview'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              _preview,
              style: const TextStyle(height: 1.35, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _copyTextFinalize();
            },
            child: const Text('Copy Text'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _messageFinalize();
            },
            child: const Text('Message'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _shareQrFinalize();
            },
            child: const Text('Share QR'),
          ),
        ],
      ),
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
          _jobChip(
              activeJob.isMultiWellJob ? 'Wells' : 'Well',
              activeJob.isMultiWellJob
                  ? activeJob.resolvedWellNames.join(', ')
                  : activeJob.primaryWell),
          _jobChip('Type', _profileDefaults.jobTypeLabel(activeJob.jobType)),
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
            SegmentedButton<_EntryTimeMode>(
              segments: const [
                ButtonSegment<_EntryTimeMode>(
                  value: _EntryTimeMode.currentTime,
                  label: Text('Current Time'),
                ),
                ButtonSegment<_EntryTimeMode>(
                  value: _EntryTimeMode.manualTime,
                  label: Text('Manual Time'),
                ),
              ],
              selected: {_entryTimeMode},
              onSelectionChanged: (selection) {
                final mode = selection.first;
                setState(() {
                  _entryTimeMode = mode;
                  if (_entryTimeMode == _EntryTimeMode.manualTime &&
                      _manualEntryTime == null) {
                    _manualEntryTime = DateTime.now();
                  }
                });
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Entry Time'),
              subtitle:
                  Text('${_entryTimeModeLabel()} • ${_entryTimeDisplay()}'),
              trailing: _entryTimeMode == _EntryTimeMode.manualTime
                  ? FilledButton(
                      onPressed: _pickManualEntryTime,
                      child: const Text('Select'),
                    )
                  : null,
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
                  'Multi-well mode: this update includes all wells saved for the selected hour.',
                  style: TextStyle(color: Colors.white70),
                ),
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
                onPressed: _activeJobRows.isEmpty ? null : _openPreviewActions,
                icon: const Icon(Icons.preview),
                label: const Text('Preview Actions'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
