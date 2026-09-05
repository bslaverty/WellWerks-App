import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/app_settings_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/report_profile_service.dart';
import 'flywheel_text_update_formatter.dart';

class ProductionTextUpdateBuilder {
  ProductionTextUpdateBuilder({
    required this.settings,
    required this.shift,
    required this.activeJob,
    required this.layout,
    required this.orderedRows,
    this.headerLines,
  });

  final AppSettingsData settings;
  final ProductionShift shift;
  final JobSetup? activeJob;
  final ReportLayoutProfile layout;
  final List<ProductionReportRow> orderedRows;
  final List<String>? headerLines;

  final JobProfileDefaultsService _profileDefaults =
      JobProfileDefaultsService();

  bool get _showVruSection => settings.isOptionalSectionEnabled('vru');
  bool get _showFlareSection => settings.isOptionalSectionEnabled('flare');
  bool get _showEcdSection => settings.isOptionalSectionEnabled('ecd');
  bool get _showFlareEcdSection => _showFlareSection || _showEcdSection;

  bool get _flareEcdGasRateEnabled {
    final setup = activeJob?.drilloutSetup;
    final raw = setup?['flareEcdGasRateEnabled'];
    if (raw is bool) return raw;
    return true;
  }

  bool get _notesSectionEnabled {
    final setup = activeJob?.drilloutSetup;
    final raw = setup?['includeNotesSection'];
    if (raw is bool) return raw;
    return true;
  }

  String get _gasUnitLabel =>
      shift.inventory.gasUnit == 'mmcfd' ? 'mmcf/d' : 'mcf/d';

  String buildPreview() {
    if (orderedRows.isEmpty) return '';

    final selectedCompany = _profileDefaults.normalizeCompany(
      activeJob?.company ?? shift.header.company,
    );
    if (activeJob != null) {
      final company = _profileDefaults.normalizeCompany(activeJob!.company);
      if (company == JobProfileDefaultsService.companyMach) {
        return _machTextPreview(activeJob!, orderedRows);
      }
      if (company == JobProfileDefaultsService.companyContinental) {
        return _continentalTextPreview(activeJob!, orderedRows);
      }
      if (company == JobProfileDefaultsService.companyFlywheel) {
        return _flywheelTextPreview(orderedRows);
      }
    }

    if (selectedCompany == JobProfileDefaultsService.companyFlywheel) {
      return _flywheelTextPreview(orderedRows);
    }

    final included =
        layout.textFields.where((field) => field.included).toList();
    final lines = _resolvedHeaderLines;
    lines.add('');

    const vruKeys = {
      'vruGasRt',
      'compressorInj',
      'vruSuction',
      'vruDischarge',
    };
    for (var i = 0; i < orderedRows.length; i++) {
      final previewRow = orderedRows[i];
      lines.add(
          previewRow.well.trim().isEmpty ? 'Well' : previewRow.well.trim());
      for (final field in included) {
        if (field.key == 'time' ||
            vruKeys.contains(field.key) ||
            field.key == 'notes' ||
            (activeJob?.usesCentralTankBattery ?? false) &&
                const {'waterGaugeText', 'oilGaugeText'}.contains(field.key)) {
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

      if (_showFlareEcdSection) {
        lines.add('');
        lines.add('FLARE / ECD');
        lines.add(
            'Temperature: ${previewRow.flarePilotTemp.isEmpty ? '-' : previewRow.flarePilotTemp} °F');
        if (_flareEcdGasRateEnabled) {
          lines.add(
              'Gas Rate: ${previewRow.flareRate.isEmpty ? '-' : _gasString(previewRow.flareRate)} $_gasUnitLabel');
        }
      }

      if (included.any((f) => f.key == 'notes') && _notesSectionEnabled) {
        lines.add('');
        lines.add('Notes');
        lines.add(_lineFor(previewRow, 'notes'));
      }

      if (i != orderedRows.length - 1) {
        lines.add('');
      }
    }

    return lines.join('\n');
  }

  List<String> get _resolvedHeaderLines {
    if (headerLines != null && headerLines!.isNotEmpty) {
      return List<String>.from(headerLines!);
    }
    final lines = <String>[];
    final company = _headerCompanyName;
    final pad = _headerPadName;
    if (company.isNotEmpty) lines.add(company);
    if (pad.isNotEmpty) lines.add(pad);
    if (_headerWellListText != '-') lines.add(_headerWellListText);
    lines.add(_headerUpdateTime);
    return lines;
  }

  String get _headerCompanyName {
    final job = activeJob;
    if (job != null && job.company.trim().isNotEmpty) {
      return job.company.trim();
    }
    return shift.header.company.trim();
  }

  String get _headerPadName {
    final job = activeJob;
    if (job != null && job.padName.trim().isNotEmpty) {
      return job.padName.trim();
    }
    return shift.header.pad.trim();
  }

  List<String> get _headerWellList {
    final wells = <String>[];
    final source = activeJob != null && activeJob!.resolvedWellNames.isNotEmpty
        ? activeJob!.resolvedWellNames
        : shift.header.wells;
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
    if (orderedRows.isNotEmpty) {
      return '${_fmtTimeLabel(orderedRows.first.time)} UPDATE';
    }
    return 'UPDATE';
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

  double _baseGasToDisplay(double value) {
    return shift.inventory.gasUnit == 'mmcfd' ? value / 1000 : value;
  }

  String _gasString(String value) {
    final parsed = double.tryParse(value.trim()) ?? 0;
    return _fmt(_baseGasToDisplay(parsed));
  }

  bool _chemicalSelected(String name) {
    final selected = activeJob?.selectedChemicals ?? const <String>[];
    return selected.any((item) => item.toLowerCase() == name.toLowerCase());
  }

  String _biocideValue(ProductionReportRow row) {
    if (!_chemicalSelected('Biocide')) {
      return 'N/A';
    }
    return row.biocide.isEmpty ? '-' : row.biocide;
  }

  String _fmtTimeLabel(String value) {
    final raw = value.trim();
    final parsed = _parseShiftTime(raw);
    if (parsed == null) {
      return raw.toUpperCase();
    }
    if (settings.textTimeFormat == '24h') {
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
      case 'tbg':
        return row.tbg.isEmpty ? '-' : row.tbg;
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

  String _machTextPreview(JobSetup job, List<ProductionReportRow> rows) {
    final defaults = _profileDefaults.profileForCompany(job.company);
    final activeSections = job.activeEquipmentSections.isEmpty
        ? defaults.defaultActiveSections
        : job.activeEquipmentSections;
    final lines = _resolvedHeaderLines;
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
      if (i != rows.length - 1) {
        lines.add('');
      }
    }
    return lines.join('\n');
  }

  String _flywheelUpdateLine(String sourceTime) {
    final parsed = _parseShiftTime(sourceTime.trim());
    if (parsed == null) {
      return '${sourceTime.trim()} update';
    }

    final hour12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    final marker = parsed.hour >= 12 ? 'pm' : 'am';
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

  String _flywheelTextPreview(List<ProductionReportRow> rows) {
    final updateRow = rows.isNotEmpty ? rows.first : null;
    final formatted = buildFlywheelTextUpdate(
      updateLine: _flywheelUpdateLine(updateRow?.time ?? ''),
      locationLine: _headerPadName,
      wells: rows
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
          .toList(),
    );
    if (headerLines != null && headerLines!.isNotEmpty) {
      return '${headerLines!.join('\n')}\n\n$formatted';
    }
    return formatted;
  }

  String _continentalTextPreview(
    JobSetup job,
    List<ProductionReportRow> rows,
  ) {
    final defaults = _profileDefaults.profileForCompany(job.company);
    final activeSections = job.activeEquipmentSections.isEmpty
        ? defaults.defaultActiveSections
        : job.activeEquipmentSections;

    final lines = _resolvedHeaderLines;
    lines.add('');

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (job.isMultiWellJob) {
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
            'Gas Rate: ${row.flareRate.isEmpty ? '-' : _gasString(row.flareRate)} $_gasUnitLabel',
          );
        }
      }

      if (activeSections.contains('VRU') && _showVruSection) {
        lines.add('');
        lines.add('VRU');
        lines.add(
          'GAS RT: ${row.vruGasRate.isEmpty ? '-' : _gasString(row.vruGasRate)} $_gasUnitLabel',
        );
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
}
