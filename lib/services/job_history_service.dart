import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_history.dart';
import '../models/job_setup.dart';
import '../models/production_shift.dart';
import 'job_storage_service.dart';
import 'jsa_storage_service.dart';
import 'report_profile_service.dart';
import 'production_shift_service.dart';

class JobHistoryService {
  static const _historyKey = 'wellwerks_local_job_history_v1';
  static const _layoutKey = 'wellwerks_layout_designer_v2';
  static const _layoutLegacyKey = 'wellwerks_layout_designer_v1';

  JobHistoryService();

  final ProductionShiftService _shiftService = ProductionShiftService();
  final JobStorageService _jobStorage = JobStorageService();
  final JsaStorageService _jsaStorage = JsaStorageService();
  final ReportProfileService _layoutProfiles = ReportProfileService();

  Future<List<ArchivedJob>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => ArchivedJob.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<ArchivedJob> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(history.take(200).map((item) => item.toJson()).toList()),
    );
  }

  Future<ArchivedJob?> loadArchivedJob(String id) async {
    final history = await loadHistory();
    for (final item in history) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<ArchivedLayoutSummary?> loadCurrentLayoutSummary() async {
    return _loadLayoutSummary();
  }

  Future<void> clearCurrentLayoutSummary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_layoutKey);
    await prefs.remove(_layoutLegacyKey);
  }

  Future<String> buildProductionReportTextForShift(
      ProductionShift shift) async {
    final layout =
        await _layoutProfiles.resolveProfile(shift.header.layoutProfileId);
    return _buildReportText(shift, layout);
  }

  Future<List<ArchivedTextUpdate>> buildTextUpdatesForShift(
    ProductionShift shift,
  ) async {
    final layout =
        await _layoutProfiles.resolveProfile(shift.header.layoutProfileId);
    return _buildTextUpdates(shift, layout);
  }

  Future<List<ArchivedJob>> searchHistory({
    String company = '',
    String pad = '',
    String well = '',
    String date = '',
  }) async {
    final history = await loadHistory();
    return history
        .where(
          (item) => item.matchesSearch(
            company: company,
            pad: pad,
            well: well,
            date: date,
          ),
        )
        .toList();
  }

  Future<ArchivedJob?> archiveCurrentJobOrShift() async {
    final activeShift = await _shiftService.loadActiveShift();
    final activeJob = await _jobStorage.loadActiveJob();
    if (_isEmptyArchive(activeShift, activeJob)) {
      return null;
    }

    final now = DateTime.now();
    final jsaDate = _shiftDate(activeShift, activeJob);
    final jsaJobId = activeJob?.id ?? activeShift.activeJobId;
    final jsa = await _jsaStorage.loadDraft(
      activeJobId: jsaJobId,
      date: jsaDate,
    );
    final layoutSummary = await _loadLayoutSummary();
    final layout = await _layoutProfiles
        .resolveProfile(activeShift.header.layoutProfileId);

    final shiftEntry = ArchivedShiftEntry(
      id: now.microsecondsSinceEpoch.toString(),
      date: _shiftDate(activeShift, activeJob),
      productionShift: activeShift.copyWith(updatedAt: now),
      productionReportText: _buildReportText(activeShift, layout),
      textUpdates: _buildTextUpdates(activeShift, layout),
      jsaDraft: jsa,
      archivedAt: now,
    );

    final history = await loadHistory();
    final archiveKey = _archiveKey(activeShift, activeJob);
    final existingIndex = history.indexWhere(
      (item) => _archiveKeyForArchivedJob(item) == archiveKey,
    );

    if (existingIndex >= 0) {
      final existing = history.removeAt(existingIndex);
      final shifts = [shiftEntry, ...existing.shifts]
        ..sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
      final updated = existing.copyWith(
        company: _company(activeShift, activeJob),
        padName: _pad(activeShift, activeJob),
        wells: _wells(activeShift, activeJob),
        jobSetup: activeJob ?? existing.jobSetup,
        layoutSummary: layoutSummary ?? existing.layoutSummary,
        shifts: shifts,
        dateRangeStart: _rangeStart(shifts, activeJob, existing.dateRangeStart),
        dateRangeEnd: _rangeEnd(shifts, activeJob, existing.dateRangeEnd),
        updatedAt: now,
      );
      history.insert(0, updated);
      await saveHistory(history);
      return updated;
    }

    final created = ArchivedJob(
      id: now.microsecondsSinceEpoch.toString(),
      company: _company(activeShift, activeJob),
      padName: _pad(activeShift, activeJob),
      dateRangeStart: _rangeStart([shiftEntry], activeJob, ''),
      dateRangeEnd: _rangeEnd([shiftEntry], activeJob, ''),
      wells: _wells(activeShift, activeJob),
      jobSetup: activeJob,
      layoutSummary: layoutSummary,
      shifts: [shiftEntry],
      updatedAt: now,
    );
    history.insert(0, created);
    await saveHistory(history);
    return created;
  }

  Future<void> deleteArchivedJob(String id) async {
    final history = await loadHistory();
    final next = history.where((item) => item.id != id).toList();
    await saveHistory(next);
  }

  Future<void> duplicateArchivedJobToActive(ArchivedJob job) async {
    final latest = job.shifts.isEmpty ? null : job.shifts.first;
    if (latest != null) {
      await _shiftService.saveActiveShift(latest.productionShift.copyWith(
        updatedAt: DateTime.now(),
      ));
    }
    final jobSetup = job.jobSetup ??
        JobSetup(
          company: job.company.isEmpty ? 'Mach Energy' : job.company,
          padName: job.padName,
          dateStarted: job.dateRangeStart,
          wells: job.wells,
        );
    await _jobStorage.saveActiveJob(jobSetup);
  }

  Future<ArchivedLayoutSummary?> _loadLayoutSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_layoutKey) ?? prefs.getString(_layoutLegacyKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(raw) as Map<dynamic, dynamic>,
      );
      final items = (data['items'] as List?) ?? const [];
      return ArchivedLayoutSummary(
        name: data['name'] as String? ?? 'Saved Layout',
        itemCount: items.length,
        layoutData: data,
      );
    } catch (_) {
      return null;
    }
  }

  String _archiveKey(ProductionShift shift, JobSetup? job) {
    final wells = _wells(shift, job).map((item) => item.toLowerCase()).toList()
      ..sort();
    return '${_company(shift, job).toLowerCase()}|${_pad(shift, job).toLowerCase()}|${wells.join(',')}';
  }

  String _archiveKeyForArchivedJob(ArchivedJob job) {
    final wells = job.wells.map((item) => item.toLowerCase()).toList()..sort();
    return '${job.company.toLowerCase()}|${job.padName.toLowerCase()}|${wells.join(',')}';
  }

  String _company(ProductionShift shift, JobSetup? job) {
    return shift.header.company.trim().isNotEmpty
        ? shift.header.company.trim()
        : (job?.company.trim() ?? '');
  }

  String _pad(ProductionShift shift, JobSetup? job) {
    return shift.header.pad.trim().isNotEmpty
        ? shift.header.pad.trim()
        : (job?.padName.trim() ?? '');
  }

  List<String> _wells(ProductionShift shift, JobSetup? job) {
    final source = shift.header.wells.isNotEmpty
        ? shift.header.wells
        : (job?.wells ?? const []);
    return source.where((item) => item.trim().isNotEmpty).toList();
  }

  String _shiftDate(ProductionShift shift, JobSetup? job) {
    if (shift.header.date.trim().isNotEmpty) return shift.header.date.trim();
    if ((job?.dateStarted.trim() ?? '').isNotEmpty) {
      return job!.dateStarted.trim();
    }
    return DateTime.now().toIso8601String().split('T').first;
  }

  String _rangeStart(
      List<ArchivedShiftEntry> shifts, JobSetup? job, String fallback) {
    final dates = shifts
        .map((item) => item.date)
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (dates.isEmpty) {
      final fromJob = job?.dateStarted.trim() ?? '';
      return fromJob.isNotEmpty ? fromJob : fallback;
    }
    dates.sort(_compareDateText);
    return dates.first;
  }

  String _rangeEnd(
      List<ArchivedShiftEntry> shifts, JobSetup? job, String fallback) {
    final dates = shifts
        .map((item) => item.date)
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (dates.isEmpty) {
      final fromJob = job?.dateStarted.trim() ?? '';
      return fromJob.isNotEmpty ? fromJob : fallback;
    }
    dates.sort(_compareDateText);
    return dates.last;
  }

  int _compareDateText(String a, String b) {
    final aDate = _parseDateText(a);
    final bDate = _parseDateText(b);
    if (aDate == null && bDate == null) return a.compareTo(b);
    if (aDate == null) return -1;
    if (bDate == null) return 1;
    return aDate.compareTo(bDate);
  }

  DateTime? _parseDateText(String value) {
    final iso = DateTime.tryParse(value.trim());
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final parts = value.trim().split('/');
    if (parts.length == 3) {
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  bool _isEmptyArchive(ProductionShift shift, JobSetup? job) {
    final hasJob = job != null &&
        ([job.company, job.padName, ...job.wells]
            .any((item) => item.trim().isNotEmpty));
    final header = shift.header;
    final inventory = shift.inventory;
    final hasHeader = [
      header.company,
      header.pad,
      header.date,
      header.chokeType,
    ].any((value) => value.trim().isNotEmpty);
    final hasInventory = inventory.startingGasAccum.trim().isNotEmpty ||
        inventory.waterTanks.any((tank) =>
            tank.name.trim().isNotEmpty ||
            tank.gauge.trim().isNotEmpty ||
            tank.bblPerInch.trim().isNotEmpty) ||
        inventory.oilTanks.any((tank) =>
            tank.name.trim().isNotEmpty ||
            tank.gauge.trim().isNotEmpty ||
            tank.bblPerInch.trim().isNotEmpty);
    final hasShift = hasHeader ||
        hasInventory ||
        shift.hourlyChecks.isNotEmpty ||
        shift.savedRows.isNotEmpty;
    return !hasJob && !hasShift;
  }

  String _fmt(double value) {
    final rounded = value.abs() < 0.01 ? 0 : value;
    return rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  double _baseGasToDisplay(ProductionShift shift, double value) {
    return shift.inventory.gasUnit == 'mmcfd' ? value / 1000 : value;
  }

  String _gasUnitLabel(ProductionShift shift) {
    return shift.inventory.gasUnit == 'mmcfd' ? 'mmcf/d' : 'mcf/d';
  }

  String _headerLabel(List<ReportField> fields, String key) {
    switch (key) {
      case 'gasSpotRt':
        return 'GAS RATE';
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
        return fields
            .firstWhere((f) => f.key == key,
                orElse: () => ReportField(key: key, label: key))
            .label;
    }
  }

  String _chk(ProductionReportRow row) {
    final value = row.choke.trim();
    if (value.isEmpty) return '-';
    return '$value ${row.chokeType}';
  }

  String _valueFor(ProductionShift shift, ProductionReportRow row, String key) {
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
        return _fmt(_baseGasToDisplay(shift, row.gas24HourRate));
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
        return _fmt(
            _baseGasToDisplay(shift, double.tryParse(row.flareRate) ?? 0));
      case 'flarePilotTemp':
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
        return _fmt(
            _baseGasToDisplay(shift, double.tryParse(row.vruGasRate) ?? 0));
      case 'compressorInj':
        return _fmt(_baseGasToDisplay(
            shift,
            row.compressorInjection.isEmpty
                ? 0
                : (double.tryParse(row.compressorInjection) ?? 0)));
      case 'vruSuction':
        return row.vruSuction;
      case 'vruDischarge':
        return row.vruDischarge;
      case 'notes':
        return row.notes;
      case 'waterHauled':
        return _fmt(row.waterHauled);
      case 'oilHauled':
        return _fmt(row.oilHauled);
      case 'waterMeterReading':
        return row.currentWaterMeter < 0 ? '' : _fmt(row.currentWaterMeter);
      case 'waterMeterIncrease':
        final previous = shift.savedRows
            .where((item) =>
                item.well == row.well && item.hourIndex < row.hourIndex)
            .toList()
          ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
        if (previous.isEmpty || row.currentWaterMeter < 0) return '';
        return _fmt(row.currentWaterMeter - previous.last.currentWaterMeter);
      default:
        return '';
    }
  }

  String _buildReportText(ProductionShift shift, ReportLayoutProfile layout) {
    if (shift.savedRows.isEmpty) {
      return 'No saved Production Report rows yet. Save hours in Quick Round first.';
    }
    final visible =
        layout.reportFields.where((field) => field.included).toList();
    final lines = <String>['Production Report (${layout.name})', ''];
    for (final row in shift.savedRows) {
      lines.add('${row.time} | ${row.well}');
      for (final field in visible) {
        final value = _valueFor(shift, row, field.key);
        if (value.trim().isEmpty && !field.required) {
          continue;
        }
        lines.add(
            '${_headerLabel(layout.reportFields, field.key)}: ${value.isEmpty ? '-' : value}');
      }
      if (row != shift.savedRows.last) {
        lines.add('');
      }
    }
    return lines.join('\n');
  }

  String _fmtTimeLabel(String value) {
    final parts = value.trim().split(' ');
    if (parts.length != 2) return value.toUpperCase();
    return '${parts[0]}:00 ${parts[1].toUpperCase()}';
  }

  String _textLine(ProductionShift shift, ProductionReportRow row, String key) {
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
        return 'GAS RATE ${_fmt(_baseGasToDisplay(shift, row.gas24HourRate))} ${_gasUnitLabel(shift)}';
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
        return 'FLARE RT - ${row.flareRate.isEmpty ? '-' : _fmt(_baseGasToDisplay(shift, double.tryParse(row.flareRate) ?? 0))} ${_gasUnitLabel(shift)}';
      case 'flarePilotTemp':
        return 'FLARE PILOT TEMP - ${row.flarePilotTemp.isEmpty ? '-' : row.flarePilotTemp}°';
      case 'biocide':
        return 'BIOCIDE - ${row.biocide.isEmpty ? '-' : row.biocide} GPD';
      case 'scavenger':
        return 'SCAVENGER - ${row.scavenger.isEmpty ? '-' : row.scavenger} GPD';
      case 'defoamer':
        return 'DEFOAMER - ${row.defoamer.isEmpty ? '-' : row.defoamer} GPD';
      case 'scaleInhibitor':
        return 'SCALE INHIBITOR - ${row.scaleInhibitor.isEmpty ? '-' : row.scaleInhibitor} GPD';
      case 'vruGasRt':
        return 'GAS RT - ${row.vruGasRate.isEmpty ? '-' : _fmt(_baseGasToDisplay(shift, double.tryParse(row.vruGasRate) ?? 0))} ${_gasUnitLabel(shift)}';
      case 'compressorInj':
        return 'COMP INJ - ${row.compressorInjection.isEmpty ? '-' : _fmt(_baseGasToDisplay(shift, double.tryParse(row.compressorInjection) ?? 0))} ${_gasUnitLabel(shift)}';
      case 'vruSuction':
        return 'SUCTION - ${row.vruSuction.isEmpty ? '-' : row.vruSuction}';
      case 'vruDischarge':
        return 'DISCHARGE - ${row.vruDischarge.isEmpty ? '-' : row.vruDischarge}';
      case 'notes':
        return row.notes.isEmpty ? '-' : row.notes;
      case 'waterHauled':
        return 'WATER HAULED - ${_fmt(row.waterHauled)} BBL';
      case 'oilHauled':
        return 'OIL HAULED - ${_fmt(row.oilHauled)} BBL';
      case 'waterMeterReading':
        return 'WATER METER READING - ${row.currentWaterMeter < 0 ? '-' : _fmt(row.currentWaterMeter)}';
      case 'waterMeterIncrease':
        return 'WATER METER INCREASE - ${_valueFor(shift, row, key)}';
      default:
        return '';
    }
  }

  List<ArchivedTextUpdate> _buildTextUpdates(
    ProductionShift shift,
    ReportLayoutProfile layout,
  ) {
    final included =
        layout.textFields.where((field) => field.included).toList();
    final vruKeys = {'vruGasRt', 'compressorInj', 'vruSuction', 'vruDischarge'};
    final pad = shift.header.pad.trim().isEmpty ? '-' : shift.header.pad.trim();

    return shift.savedRows.map((row) {
      final lines = <String>[pad, '${_fmtTimeLabel(row.time)} UPDATE', ''];
      for (final field in included) {
        if (vruKeys.contains(field.key) || field.key == 'notes') continue;
        final raw = _valueFor(shift, row, field.key);
        if (raw.trim().isEmpty && !field.required) continue;
        final line = _textLine(shift, row, field.key);
        if (line.isNotEmpty) lines.add(line);
      }
      final hasVru = included.any((field) => vruKeys.contains(field.key));
      if (hasVru) {
        final vruLines = <String>[];
        for (final field
            in included.where((item) => vruKeys.contains(item.key))) {
          final raw = _valueFor(shift, row, field.key);
          if (raw.trim().isEmpty && !field.required) continue;
          vruLines.add(_textLine(shift, row, field.key));
        }
        if (vruLines.isNotEmpty) {
          lines.add('');
          lines.add('VRU');
          lines.add('');
          lines.addAll(vruLines);
        }
      }
      if (included.any((field) => field.key == 'notes')) {
        final rawNotes = _valueFor(shift, row, 'notes');
        if (rawNotes.trim().isNotEmpty) {
          lines.add('');
          lines.add('Notes');
          lines.add(_textLine(shift, row, 'notes'));
        }
      }
      final extraKeys = <String>[
        if (shift.inventory.useWaterHauled) 'waterHauled',
        if (shift.inventory.useOilHauled) 'oilHauled',
        if (shift.inventory.useWaterMeter) 'waterMeterReading',
        if (shift.inventory.useWaterMeter) 'waterMeterIncrease',
      ];
      for (final key in extraKeys) {
        final line = _textLine(shift, row, key);
        if (line.isNotEmpty) lines.add(line);
      }
      return ArchivedTextUpdate(
        hourIndex: row.hourIndex,
        time: row.time,
        content: lines.join('\n'),
      );
    }).toList();
  }
}
