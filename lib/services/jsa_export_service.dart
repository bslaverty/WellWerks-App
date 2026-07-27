import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../models/jsa_template.dart';
import '../utils/jsa_time_format.dart';

class ExportedJsaFile {
  const ExportedJsaFile({
    required this.filePath,
    required this.fileName,
  });

  final String filePath;
  final String fileName;
}

class JsaExportService {
  JsaExportService({
    Future<List<Uint8List>> Function(Uint8List pdfBytes)? rasterizer,
  }) : _rasterizer = rasterizer;

  final Future<List<Uint8List>> Function(Uint8List pdfBytes)? _rasterizer;

  static const List<String> _supportedPpe = <String>[
    'Hard Hat',
    'Safety Glasses',
    'FR Clothing',
    'Impact Gloves',
    'Safety Boots',
    'Gas Monitor',
    'Hearing Protection',
  ];

  static const PdfColor _gold = PdfColor.fromInt(0xFFCDA56A);
  static const PdfColor _line = PdfColor.fromInt(0xFFD5D9DE);
  static const PdfColor _headerFill = PdfColor.fromInt(0xFFF5F7FA);

  Future<ExportedJsaFile> exportPdf({
    required JsaDraft draft,
    JobSetup? activeJob,
    String? baseFileName,
  }) async {
    final bytes = await buildPdfBytes(draft: draft, activeJob: activeJob);
    final fileName = _buildFileName(
      draft: draft,
      extension: 'pdf',
      baseFileName: baseFileName,
    );
    final directory = await _ensureExportDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return ExportedJsaFile(filePath: file.path, fileName: fileName);
  }

  Future<List<ExportedJsaFile>> exportPageImages({
    required JsaDraft draft,
    JobSetup? activeJob,
    String? baseFileName,
  }) async {
    final pdfBytes = await buildPdfBytes(draft: draft, activeJob: activeJob);
    final pngPages = await _renderPdfPagesToPng(pdfBytes);
    final safeBase = _sanitizeBaseName(
      baseFileName ?? suggestBaseFileName(draft),
    );

    final directory = await _ensureExportDirectory();
    final files = <ExportedJsaFile>[];
    for (var index = 0; index < pngPages.length; index++) {
      final fileName = '${safeBase}_Page-${index + 1}.png';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(pngPages[index], flush: true);
      files.add(ExportedJsaFile(filePath: file.path, fileName: fileName));
    }
    return files;
  }

  Future<Uint8List> buildPdfBytes({
    required JsaDraft draft,
    JobSetup? activeJob,
  }) async {
    final doc = pw.Document(compress: false);
    final cityState = _splitCityState(draft.cityState);
    final stepRows = _mapStepRows(
      steps: draft.steps,
      hazards: draft.hazards,
      recommendations: draft.recommendations,
    );
    final ppeRows = _buildPpeRows(draft);

    final logo = await _loadLogoBytes();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
        header: (context) => _documentHeader(logo),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 8),
          _jobInfoTable(draft, activeJob: activeJob, cityState: cityState),
          pw.SizedBox(height: 12),
          _sectionTitle('Step / Hazard / Recommended Action'),
          _stepsTable(stepRows),
          pw.SizedBox(height: 12),
          _sectionTitle('PPE'),
          _ppeTable(ppeRows),
          pw.SizedBox(height: 12),
          _sectionTitle('Employees and Signatures'),
          _employeesTable(draft.employees),
          pw.SizedBox(height: 12),
          _sectionTitle('Notes / Comments'),
          ..._notesWidgets(draft.notes),
        ],
      ),
    );

    return doc.save();
  }

  Future<Directory> _ensureExportDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/wellwerks_jsa_exports');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _buildFileName({
    required JsaDraft draft,
    required String extension,
    String? baseFileName,
  }) {
    final base = baseFileName?.trim().isNotEmpty == true
        ? baseFileName!.trim()
        : suggestBaseFileName(draft);
    final safeBase = _sanitizeBaseName(base);
    return '$safeBase.$extension';
  }

  String suggestBaseFileName(JsaDraft draft) {
    final company = draft.company.trim();
    final wellName = draft.wellName.trim();
    final location = draft.location.trim();

    final parts = <String>[
      draft.date.trim(),
      if (company.isNotEmpty) company,
      if (wellName.isNotEmpty) wellName else if (location.isNotEmpty) location,
      'JSA',
    ];
    return _sanitizeBaseName(parts.join('_'));
  }

  String _sanitizeBaseName(String raw) {
    var value = raw.trim();
    value = value.replaceAll(RegExp(r'\.(pdf|png)$', caseSensitive: false), '');
    value = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return value.isEmpty ? 'jsa' : value;
  }

  Future<List<Uint8List>> _renderPdfPagesToPng(Uint8List pdfBytes) async {
    if (_rasterizer != null) {
      return _rasterizer(pdfBytes);
    }

    final pages = <Uint8List>[];
    await for (final page in Printing.raster(pdfBytes, dpi: 160)) {
      pages.add(await page.toPng());
    }
    return pages;
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final candidates = <String>[
      'assets/images/app-icon.png',
      'assets/icons/app_icon.png',
    ];

    for (final path in candidates) {
      try {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List();
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  pw.Widget _documentHeader(Uint8List? logoBytes) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 44,
            height: 44,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: logoBytes == null
                ? pw.Text(
                    'WW',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _gold,
                    ),
                  )
                : pw.Image(
                    pw.MemoryImage(logoBytes),
                    fit: pw.BoxFit.contain,
                  ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'WellWerks JSA',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: _gold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Job Safety Analysis',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _jobInfoTable(
    JsaDraft draft, {
    required JobSetup? activeJob,
    required ({String city, String state}) cityState,
  }) {
    final jsaType = draft.templateName.trim().isNotEmpty
        ? draft.templateName.trim()
        : (draft.task.trim().isEmpty ? 'General' : draft.task.trim());

    final jobRows = <List<String>>[
      <String>['Company / Customer', _safe(draft.company)],
      <String>[
        'Customer / PIC',
        [activeJob?.customer.trim() ?? '', activeJob?.crew.trim() ?? '']
            .where((item) => item.isNotEmpty)
            .join(' / ')
      ],
      <String>['Date', _safe(draft.date)],
      <String>['Time', _safe(formatStoredJsaTime(draft.time))],
      <String>['JSA Type / Template', _safe(jsaType)],
      <String>['Location / Pad', _safe(draft.location)],
      <String>['Well Name', _safe(draft.wellName)],
      <String>['County', _safe(draft.county)],
      <String>['City', _safe(cityState.city)],
      <String>['State', _safe(cityState.state)],
      <String>['GPS Coordinates', _safe(draft.gpsCoordinates)],
      <String>[
        'Emergency Hospital / ED',
        _safe(draft.emergencyHospitalName),
      ],
      <String>[
        'Hospital Address',
        _safe(draft.emergencyHospitalAddress),
      ],
      <String>[
        'Hospital Coordinates',
        _safe(draft.emergencyHospitalCoordinates),
      ],
      <String>['Temperature', _safe(draft.weatherTemperature)],
      <String>['Wind', _safe(draft.weatherWind)],
      <String>['Conditions', _safe(draft.weatherConditions)],
    ];

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF5F7FA),
            ),
            child: pw.Text(
              'Job Information',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _gold,
                fontSize: 11,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Table(
              border: pw.TableBorder.all(color: _line, width: 0.5),
              columnWidths: const <int, pw.TableColumnWidth>{
                0: pw.FlexColumnWidth(23),
                1: pw.FlexColumnWidth(27),
                2: pw.FlexColumnWidth(23),
                3: pw.FlexColumnWidth(27),
              },
              children: [
                for (var i = 0; i < jobRows.length; i += 2)
                  pw.TableRow(
                    children: [
                      _labelCell(jobRows[i][0]),
                      _valueCell(jobRows[i][1]),
                      _labelCell(
                          i + 1 < jobRows.length ? jobRows[i + 1][0] : ''),
                      _valueCell(
                          i + 1 < jobRows.length ? jobRows[i + 1][1] : ''),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _stepsTable(List<_StepRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(24),
        1: pw.FlexColumnWidth(34),
        2: pw.FlexColumnWidth(42),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF5F7FA),
          ),
          children: [
            _headerCell('Basic Job Step'),
            _headerCell('Potential Incident / Hazard'),
            _headerCell('Recommended Action'),
          ],
        ),
        if (rows.isEmpty)
          pw.TableRow(
            children: [
              _valueCell('No steps selected.'),
              _valueCell(''),
              _valueCell(''),
            ],
          ),
        for (final row in rows)
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.top,
            children: [
              _valueCell(row.step),
              _bulletedCell(row.hazards),
              _bulletedCell(row.recommendations),
            ],
          ),
      ],
    );
  }

  pw.Widget _ppeTable(List<({String label, bool selected})> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(25),
        1: pw.FlexColumnWidth(25),
        2: pw.FlexColumnWidth(25),
        3: pw.FlexColumnWidth(25),
      },
      children: [
        for (var i = 0; i < rows.length; i += 4)
          pw.TableRow(
            children: [
              _ppeCell(rows[i]),
              _ppeCell(i + 1 < rows.length
                  ? rows[i + 1]
                  : (label: '', selected: false)),
              _ppeCell(i + 2 < rows.length
                  ? rows[i + 2]
                  : (label: '', selected: false)),
              _ppeCell(i + 3 < rows.length
                  ? rows[i + 3]
                  : (label: '', selected: false)),
            ],
          ),
      ],
    );
  }

  pw.Widget _employeesTable(List<JsaEmployee> employees) {
    final rows = List<JsaEmployee>.from(employees);
    while (rows.length < 6) {
      rows.add(JsaEmployee());
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(30),
        1: pw.FlexColumnWidth(30),
        2: pw.FlexColumnWidth(40),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF5F7FA),
          ),
          children: [
            _headerCell('Employee Name'),
            _headerCell('Company'),
            _headerCell('Signature'),
          ],
        ),
        for (final employee in rows)
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              _valueCell(_safe(employee.name)),
              _valueCell(_safe(employee.company)),
              _signatureCell(employee.signaturePngBase64),
            ],
          ),
      ],
    );
  }

  List<pw.Widget> _notesWidgets(String notes) {
    final safe = _safe(notes);
    final lines = safe.split('\n').map((line) => line.trim()).toList();
    final visible = lines.where((line) => line.isNotEmpty).toList();
    if (visible.isEmpty) {
      return <pw.Widget>[
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text('-', style: const pw.TextStyle(fontSize: 10.5)),
        ),
      ];
    }

    return <pw.Widget>[
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final line in visible)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(line, style: const pw.TextStyle(fontSize: 10.2)),
              ),
          ],
        ),
      ),
    ];
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: _headerFill,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: _gold,
          fontWeight: pw.FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _labelCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9.4,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _valueCell(String text) {
    final safe = _safe(text);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        safe.isEmpty ? '-' : safe,
        style: const pw.TextStyle(fontSize: 9.4),
      ),
    );
  }

  pw.Widget _bulletedCell(List<String> lines) {
    final items = lines
        .map((item) => _stripBullet(item.trim()))
        .where((item) => item.isNotEmpty)
        .toList();
    if (items.isEmpty) {
      return _valueCell('');
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text('- ${_safe(line)}',
                  style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.25)),
            ),
        ],
      ),
    );
  }

  pw.Widget _signatureCell(String? signatureBase64) {
    final raw = (signatureBase64 ?? '').trim();
    if (raw.isEmpty) {
      return _valueCell('');
    }

    try {
      final bytes = base64Decode(raw);
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Container(
          height: 48,
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(
            pw.MemoryImage(bytes),
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    } catch (_) {
      return _valueCell('');
    }
  }

  pw.Widget _ppeCell(({String label, bool selected}) item) {
    final label = item.label.trim();
    if (label.isEmpty) {
      return _valueCell('');
    }
    final mark = item.selected ? '[x]' : '[ ]';
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        '$mark ${_safe(label)}',
        style: const pw.TextStyle(fontSize: 9.2),
      ),
    );
  }

  List<({String label, bool selected})> _buildPpeRows(JsaDraft draft) {
    final selected = _selectedPpeForDraft(draft)
        .map((item) => item.trim().toLowerCase())
        .toSet();

    return _supportedPpe
        .map((item) =>
            (label: item, selected: selected.contains(item.toLowerCase())))
        .toList();
  }

  List<String> _selectedPpeForDraft(JsaDraft draft) {
    final byId = JsaBuiltInTemplates.byId(draft.templateId);
    if (byId != null) {
      return byId.requiredPpe;
    }
    final byName = JsaBuiltInTemplates.byName(draft.templateName);
    if (byName != null) {
      return byName.requiredPpe;
    }
    return const <String>[];
  }

  List<_StepRow> _mapStepRows({
    required List<String> steps,
    required List<String> hazards,
    required List<String> recommendations,
  }) {
    final cleanSteps = steps
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final hazardGroups = _groupItemsByStep(hazards, cleanSteps.length);
    final recommendationGroups =
        _groupItemsByStep(recommendations, cleanSteps.length);

    return List<_StepRow>.generate(
      cleanSteps.length,
      (index) => _StepRow(
        step: cleanSteps[index],
        hazards: hazardGroups[index] ?? const <String>[],
        recommendations: recommendationGroups[index] ?? const <String>[],
      ),
    );
  }

  Map<int, List<String>> _groupItemsByStep(List<String> lines, int stepCount) {
    final map = <int, List<String>>{};
    final clean = lines
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (clean.isEmpty || stepCount <= 0) {
      return map;
    }

    final hasMarkers = clean.any((item) => _stepIndexMarker(item) != null);
    if (!hasMarkers) {
      for (var i = 0; i < clean.length && i < stepCount; i++) {
        map.putIfAbsent(i, () => <String>[]).add(_stripBullet(clean[i]));
      }
      return map;
    }

    var currentStep = 0;
    for (final item in clean) {
      final marker = _stepIndexMarker(item);
      if (marker != null) {
        currentStep = marker;
        continue;
      }
      if (currentStep >= 0 && currentStep < stepCount) {
        map.putIfAbsent(currentStep, () => <String>[]).add(_stripBullet(item));
      }
    }
    return map;
  }

  int? _stepIndexMarker(String value) {
    final match = RegExp(r'^STEP\s+(\d+)$', caseSensitive: false)
        .firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final number = int.tryParse(match.group(1) ?? '');
    if (number == null || number <= 0) {
      return null;
    }
    return number - 1;
  }

  String _stripBullet(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('•')) {
      return trimmed.substring(1).trim();
    }
    if (trimmed.startsWith('-')) {
      return trimmed.substring(1).trim();
    }
    return trimmed;
  }

  ({String city, String state}) _splitCityState(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return (city: '', state: '');
    }
    final parts = value.split(',');
    if (parts.length < 2) {
      return (city: value, state: '');
    }
    return (city: parts.first.trim(), state: parts.sublist(1).join(',').trim());
  }

  String _safe(String value) {
    final trimmed = value.trim();
    return trimmed.replaceAll('₂', '2');
  }
}

class _StepRow {
  const _StepRow({
    required this.step,
    required this.hazards,
    required this.recommendations,
  });

  final String step;
  final List<String> hazards;
  final List<String> recommendations;
}
