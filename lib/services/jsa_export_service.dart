import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/job_setup.dart';
import '../models/jsa_draft.dart';

class ExportedJsaFile {
  const ExportedJsaFile({
    required this.filePath,
    required this.fileName,
  });

  final String filePath;
  final String fileName;
}

class JsaExportService {
  const JsaExportService();

  Future<ExportedJsaFile> exportPdf({
    required JsaDraft draft,
    JobSetup? activeJob,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _header(draft),
          pw.SizedBox(height: 10),
          _infoSection(draft),
          pw.SizedBox(height: 10),
          _listSection('Selected Steps', draft.tasks),
          _listSection('Basic Steps', draft.steps),
          _listSection('Hazards', draft.hazards),
          _listSection('Recommendations', draft.recommendations),
          _employeesSection(draft.employees),
          _notesSection(draft.notes),
        ],
      ),
    );

    final fileName = _buildFileName(draft: draft, extension: 'pdf');
    final directory = await _ensureExportDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(await doc.save(), flush: true);
    return ExportedJsaFile(filePath: file.path, fileName: fileName);
  }

  Future<ExportedJsaFile> exportImage({
    required JsaDraft draft,
    required Uint8List pngBytes,
  }) async {
    final fileName = _buildFileName(draft: draft, extension: 'png');
    final directory = await _ensureExportDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pngBytes, flush: true);
    return ExportedJsaFile(filePath: file.path, fileName: fileName);
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
  }) {
    final parts = <String>[
      draft.date.trim(),
      draft.company.trim(),
      draft.location.trim(),
    ].where((item) => item.isNotEmpty).toList();
    final base = parts.isEmpty ? 'jsa' : parts.join('_');
    final safeBase = base
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final readableBase = safeBase.isEmpty ? 'jsa' : safeBase;
    return '${readableBase}_JSA.$extension';
  }

  pw.Widget _header(JsaDraft draft) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF6E6CC),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'WellWerks JSA',
            style: const pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFCDA56A),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _safe(draft.company),
            style: const pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _infoSection(JsaDraft draft) {
    final rows = <List<String>>[
      ['Date', _safe(draft.date)],
      ['Time', _safe(draft.time)],
      ['Company', _safe(draft.company)],
      ['Location / Pad', _safe(draft.location)],
      ['County', _safe(draft.county)],
      ['City, State', _safe(draft.cityState)],
      ['GPS Coordinates', _safe(draft.gpsCoordinates)],
      ['Temperature', _safe(draft.weatherTemperature)],
      ['Wind', _safe(draft.weatherWind)],
      ['Conditions', _safe(draft.weatherConditions)],
    ];

    return _sectionCard(
      'Job Information',
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows.map((row) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 78,
                  child: pw.Text(
                    row[0],
                    style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(child: pw.Text(row[1])),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  pw.Widget _listSection(String title, List<String> items) {
    final visibleItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return _sectionCard(
      title,
      visibleItems.isEmpty
          ? pw.Text('None entered.')
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: visibleItems
                  .map(
                    (item) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('• $item'),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  pw.Widget _employeesSection(List<JsaEmployee> employees) {
    final visibleEmployees = employees.where((employee) {
      return employee.name.trim().isNotEmpty ||
          employee.company.trim().isNotEmpty ||
          (employee.signaturePngBase64 ?? '').trim().isNotEmpty;
    }).toList();

    return _sectionCard(
      'Employees & Signatures',
      visibleEmployees.isEmpty
          ? pw.Text('No employees entered.')
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final employee in visibleEmployees)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          employee.name.trim().isEmpty
                              ? 'Unnamed employee'
                              : employee.name.trim(),
                          style: const pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          employee.company.trim().isEmpty
                              ? 'Company not entered'
                              : employee.company.trim(),
                        ),
                        if ((employee.signaturePngBase64 ?? '')
                            .trim()
                            .isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 6),
                            child: pw.Container(
                              height: 70,
                              width: 180,
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: PdfColors.grey400),
                              ),
                              child: pw.Image(
                                pw.MemoryImage(
                                  base64Decode(employee.signaturePngBase64!),
                                ),
                                fit: pw.BoxFit.contain,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  pw.Widget _notesSection(String notes) {
    return _sectionCard(
      'Notes / Comments',
      pw.Text(_safe(notes)),
    );
  }

  pw.Widget _sectionCard(String title, pw.Widget child) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFCDA56A),
            ),
          ),
          pw.SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  String _safe(String value) {
    final trimmed = value.trim();
    return trimmed;
  }
}
