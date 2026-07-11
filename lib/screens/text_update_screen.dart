import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../services/job_profile_defaults_service.dart';
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
  final _settingsService = AppSettingsService();
  final _shiftService = ProductionShiftService();
  final _layoutService = ReportProfileService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _profileDefaults = JobProfileDefaultsService();

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
    _recoveryState.saveLastModule(RecoveryModules.textUpdate);
    _load();
  }

  Future<void> _load() async {
    var shift = await _shiftService.loadActiveShift();
    final settings = await _settingsService.load();
    final activeJob = await _jobStorage.loadActiveJob();
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
          (rows.isEmpty ? null : rows.first.hourIndex);
      _loading = false;
    });
  }

  List<ProductionReportRow> get _activeJobRows {
    final inventoryRows = _shift.inventory.productionRows.isNotEmpty
        ? _shift.inventory.productionRows
        : _shift.savedRows;
    final activeJob = _activeJob;
    final rows = activeJob == null
        ? List<ProductionReportRow>.from(inventoryRows)
        : (_shift.activeJobId != activeJob.id
            ? <ProductionReportRow>[]
            : List<ProductionReportRow>.from(inventoryRows));
    final order = _shift.header.wells;
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

  bool get _showVruSection => _settings.isOptionalSectionEnabled('vru');

  bool get _showFlareSection => _settings.isOptionalSectionEnabled('flare');

  bool get _showEcdSection => _settings.isOptionalSectionEnabled('ecd');

  String _fmtTimeLabel(String value) {
    final raw = value.trim();
    final parsed = _parseShiftTime(raw);
    if (parsed == null) {
      return raw.toUpperCase();
    }
    if (_settings.textTimeFormat == '24h') {
      final hh = parsed.hour.toString().padLeft(2, '0');
      final mm = parsed.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    final period = parsed.hour >= 12 ? 'PM' : 'AM';
    final hour12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final mm = parsed.minute.toString().padLeft(2, '0');
    return '$hour12:$mm $period';
  }

  DateTime? _parseShiftTime(String value) {
    final upper = value.trim().toUpperCase();
    if (upper.isEmpty) return null;

    final twelve = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([AP]M)$');
    final twelveMatch = twelve.firstMatch(upper);
    if (twelveMatch != null) {
      final hourRaw = int.tryParse(twelveMatch.group(1) ?? '');
      final minuteRaw = int.tryParse(twelveMatch.group(2) ?? '00') ?? 0;
      final marker = twelveMatch.group(3) ?? 'AM';
      if (hourRaw == null || hourRaw < 1 || hourRaw > 12 || minuteRaw > 59) {
        return null;
      }
      var hour = hourRaw % 12;
      if (marker == 'PM') {
        hour += 12;
      }
      return DateTime(2000, 1, 1, hour, minuteRaw);
    }

    final twentyFour = RegExp(r'^(\d{1,2}):(\d{2})$');
    final twentyFourMatch = twentyFour.firstMatch(upper);
    if (twentyFourMatch != null) {
      final hour = int.tryParse(twentyFourMatch.group(1) ?? '');
      final minute = int.tryParse(twentyFourMatch.group(2) ?? '');
      if (hour == null || minute == null || hour > 23 || minute > 59) {
        return null;
      }
      return DateTime(2000, 1, 1, hour, minute);
    }

    return null;
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
    final source = activeJob?.wells.isNotEmpty == true
        ? activeJob!.wells
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
    final selected = _selectedRow;
    if (selected != null) {
      return '${_fmtTimeLabel(selected.time)} UPDATE';
    }
    final selectedHour = _selectedHour;
    if (selectedHour != null && _activeJobRows.isNotEmpty) {
      final row = _activeJobRows.firstWhere(
        (item) => item.hourIndex == selectedHour,
        orElse: () => _activeJobRows.first,
      );
      return '${_fmtTimeLabel(row.time)} UPDATE';
    }
    return 'UPDATE';
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
    final order = _shift.header.wells;
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
      'clrFlarePilot',
      'clrFlareRt',
      'clrFlareTemp',
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
      case 'riserTemp':
        return 'RISER TEMP - ${row.wellheadTemp.isEmpty ? '-' : row.wellheadTemp}°';
      case 'riserPl':
        return 'RISER PL - -';
      case 'clrFlarePilot':
        return 'CLR FLARE PILOT - ${row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp}°';
      case 'clrFlareRt':
        return 'CLR FLARE Rt - ${row.flareRate.isEmpty ? '-' : _gasString(row.flareRate)} $_gasUnitLabel';
      case 'clrFlareTemp':
        return 'CLR FLARE TEMP - ${row.gasTemp.isEmpty ? '-' : row.gasTemp}°';
      case 'biocide':
        return 'BIOCIDE - ${row.biocide.isEmpty ? '-' : row.biocide} GPD';
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
        const {
          'flareRt',
          'flarePilotTemp',
          'clrFlarePilot',
          'clrFlareRt',
          'clrFlareTemp'
        }.contains(key)) {
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
      case 'riserTemp':
        return row.wellheadTemp.isEmpty ? '-' : row.wellheadTemp;
      case 'riserPl':
        return '-';
      case 'clrFlarePilot':
        return row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp;
      case 'clrFlareRt':
        return '${_gasString(row.flareRate)} $_gasUnitLabel';
      case 'clrFlareTemp':
        return row.gasTemp.isEmpty ? '-' : row.gasTemp;
      case 'biocide':
        return row.biocide.isEmpty ? '-' : row.biocide;
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
      if (_showEcdSection) {
        lines.add('');
        lines.add('ECD');
        lines.add('STATUS - ON/OFF');
        lines.add('TEMP - --');
      }
      if (i != rows.length - 1) {
        lines.add('');
      }
    }
    return lines.join('\n');
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

      if (activeSections.contains('RISER')) {
        lines.add('');
        lines.add('RISER');
        lines.add('Temp: ${row.wellheadTemp.isEmpty ? '-' : row.wellheadTemp}');
        lines.add('PL: -');
      }

      if (activeSections.contains('CLR FLARE') && _showFlareSection) {
        lines.add('');
        lines.add('CLR FLARE');
        lines.add(
            'Pilot: ${row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp}');
        lines.add(
            'FLARE Rt: ${row.flareRate.isEmpty ? '-' : _gasString(row.flareRate)} $_gasUnitLabel');
        lines.add('Temp: ${row.gasTemp.isEmpty ? '-' : row.gasTemp}');
      }

      if (_showEcdSection) {
        lines.add('');
        lines.add('ECD');
        lines.add('STATUS - ON/OFF');
        lines.add('TEMP - --');
      }

      if (activeSections.contains('VRU') && _showVruSection) {
        lines.add('');
        lines.add('VRU');
        lines.add(
            'GAS RT: ${row.vruGasRate.isEmpty ? '-' : _gasString(row.vruGasRate)} $_gasUnitLabel');
        lines.add('SUCT: ${row.vruSuction.isEmpty ? '-' : row.vruSuction}');
        lines.add('DISC: ${row.vruDischarge.isEmpty ? '-' : row.vruDischarge}');
      }

      if (activeSections.contains('Notes')) {
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
    if (activeJob != null) {
      final previewRows = _orderedSelectedRows;
      final company = _profileDefaults.normalizeCompany(activeJob.company);
      if (company == JobProfileDefaultsService.companyMach) {
        return _machTextPreview(activeJob, previewRows);
      }
      if (company == JobProfileDefaultsService.companyContinental) {
        return _continentalTextPreview(activeJob, previewRows);
      }
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
                  ? activeJob.wells.join(', ')
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
