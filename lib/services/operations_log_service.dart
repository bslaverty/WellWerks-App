import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/operations_log_entry.dart';
import 'device_identity_service.dart';
import 'drillout_cleanout_field_definitions.dart';
import 'operations_sts_reminder_service.dart';
import 'operator_profile_service.dart';
import 'wellwerks_qr_transfer_service.dart';

enum OperationsLogWorkflow { drillout, cleanout }

enum OperationsLogPackageType {
  drilloutReading,
  drilloutReadingBatch,
  cleanoutReading,
  cleanoutReadingBatch,
}

extension OperationsLogPackageTypeX on OperationsLogPackageType {
  String get value {
    switch (this) {
      case OperationsLogPackageType.drilloutReading:
        return 'drilloutReading';
      case OperationsLogPackageType.drilloutReadingBatch:
        return 'drilloutReadingBatch';
      case OperationsLogPackageType.cleanoutReading:
        return 'cleanoutReading';
      case OperationsLogPackageType.cleanoutReadingBatch:
        return 'cleanoutReadingBatch';
    }
  }

  OperationsLogWorkflow get workflow {
    switch (this) {
      case OperationsLogPackageType.drilloutReading:
      case OperationsLogPackageType.drilloutReadingBatch:
        return OperationsLogWorkflow.drillout;
      case OperationsLogPackageType.cleanoutReading:
      case OperationsLogPackageType.cleanoutReadingBatch:
        return OperationsLogWorkflow.cleanout;
    }
  }

  bool get isBatch =>
      this == OperationsLogPackageType.drilloutReadingBatch ||
      this == OperationsLogPackageType.cleanoutReadingBatch;

  static OperationsLogPackageType? fromValue(String value) {
    switch (value.trim()) {
      case 'drilloutReading':
        return OperationsLogPackageType.drilloutReading;
      case 'drilloutReadingBatch':
        return OperationsLogPackageType.drilloutReadingBatch;
      case 'cleanoutReading':
        return OperationsLogPackageType.cleanoutReading;
      case 'cleanoutReadingBatch':
        return OperationsLogPackageType.cleanoutReadingBatch;
      default:
        return null;
    }
  }
}

class OperationsLogDuplicate {
  const OperationsLogDuplicate({required this.entry});

  final OperationsLogEntry entry;
}

class OperationsLogConflict {
  const OperationsLogConflict({
    required this.existing,
    required this.incoming,
  });

  final OperationsLogEntry existing;
  final OperationsLogEntry incoming;
}

class OperationsLogImportResult {
  const OperationsLogImportResult({
    required this.added,
    required this.duplicates,
    required this.conflicts,
  });

  final List<OperationsLogEntry> added;
  final List<OperationsLogDuplicate> duplicates;
  final List<OperationsLogConflict> conflicts;

  bool get hasChanges => added.isNotEmpty;
}

class ExportedOperationsLogReportFile {
  const ExportedOperationsLogReportFile({
    required this.filePath,
    required this.fileName,
  });

  final String filePath;
  final String fileName;
}

class OperationsLogService {
  static const _packageFileType = 'wellwerks_operations_log';
  static const _schemaVersion = '1.0.0';
  static const _prefsKeyBase = 'wellwerks_operations_log_entries_v1';
  static const _historyKey = 'wellwerks_operations_log_history_v1';
  static const PdfColor _gold = PdfColor.fromInt(0xFFCDA56A);
  static const PdfColor _line = PdfColor.fromInt(0xFFD5D9DE);

  OperationsLogService({
    WellWerksQrTransferService? qrTransferService,
    OperatorProfileService? operatorProfileService,
    DeviceIdentityService? deviceIdentityService,
    OperationsStsReminderService? stsReminderService,
  })  : _qrTransferService =
            qrTransferService ?? const WellWerksQrTransferService(),
        _operatorProfileService =
            operatorProfileService ?? OperatorProfileService.instance,
        _deviceIdentityService =
            deviceIdentityService ?? DeviceIdentityService.instance,
        _stsReminderService =
            stsReminderService ?? OperationsStsReminderService();

  final WellWerksQrTransferService _qrTransferService;
  final OperatorProfileService _operatorProfileService;
  final DeviceIdentityService _deviceIdentityService;
  final OperationsStsReminderService _stsReminderService;

  String storageKey(OperationsLogWorkflow workflow, String jobId) {
    final normalizedJobId = jobId.trim();
    return normalizedJobId.isEmpty
        ? '$_prefsKeyBase:${workflow.name}'
        : '$_prefsKeyBase:${workflow.name}:$normalizedJobId';
  }

  Future<List<OperationsLogEntry>> loadEntries({
    required OperationsLogWorkflow workflow,
    required String jobId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey(workflow, jobId));
    if (raw == null || raw.isEmpty) return <OperationsLogEntry>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => OperationsLogEntry.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => a.readingTimestamp.compareTo(b.readingTimestamp));
    } catch (_) {
      return <OperationsLogEntry>[];
    }
  }

  Future<void> saveEntries({
    required OperationsLogWorkflow workflow,
    required String jobId,
    required List<OperationsLogEntry> entries,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<OperationsLogEntry>.from(entries)
      ..sort((a, b) => a.readingTimestamp.compareTo(b.readingTimestamp));
    await prefs.setString(
      storageKey(workflow, jobId),
      jsonEncode(sorted.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<OperationsLogEntry> createLocalEntry({
    required OperationsLogWorkflow workflow,
    required String jobId,
    required String wellId,
    required String wellName,
    required DateTime readingTimestamp,
    String operationStage = '',
    String choke = '',
    String casingPressure = '',
    String tubingPressure = '',
    String pumpPressure = '',
    String pumpRate = '',
    String gas = '',
    String plugNumber = '',
    String surfaceTotalFluid = '',
    String waterHauled = '',
    String oilHauled = '',
    String returnsRate = '',
    String waterRate = '',
    String flowRate = '',
    DateTime? estimatedSts,
    DateTime? sts,
    String tankLevel = '',
    String sweepInformation = '',
    String sandOrSolids = '',
    String equipmentStatus = '',
    String downtime = '',
    String notes = '',
  }) async {
    final profile = await _operatorProfileService.load();
    final deviceId = await _deviceIdentityService.load();
    final packageInfo = await PackageInfo.fromPlatform();
    final packageId = _newId('pkg');
    final now = DateTime.now();
    return OperationsLogEntry(
      entryId: _newId('entry'),
      packageCompatibleEntryId: _newId('pkgentry'),
      workflow: workflow.name,
      persistentJobId: jobId.trim(),
      persistentWellId: wellId.trim(),
      wellName: wellName.trim(),
      readingTimestamp: readingTimestamp,
      createdAt: now,
      lastModifiedAt: now,
      sourceBuildNumber: packageInfo.buildNumber,
      sourceOperatorId: profile.operatorId,
      sourceOperatorName: profile.name,
      sourceOperatorInitials: profile.initials,
      sourceDeviceId: deviceId,
      isImported: false,
      importedAt: null,
      qrPackageId: packageId,
      operationStage: operationStage,
      choke: choke,
      casingPressure: casingPressure,
      tubingPressure: tubingPressure,
      pumpPressure: pumpPressure,
      pumpRate: pumpRate,
      gas: gas,
      plugNumber: plugNumber,
      surfaceTotalFluid: surfaceTotalFluid,
      waterHauled: waterHauled,
      oilHauled: oilHauled,
      returnsRate: returnsRate,
      waterRate: waterRate,
      flowRate: flowRate,
      estimatedSts: estimatedSts,
      sts: sts,
      tankLevel: tankLevel,
      sweepInformation: sweepInformation,
      sandOrSolids: sandOrSolids,
      equipmentStatus: equipmentStatus,
      downtime: downtime,
      notes: notes,
    );
  }

  Future<void> upsertEntry({
    required OperationsLogWorkflow workflow,
    required String jobId,
    required OperationsLogEntry entry,
  }) async {
    final entries = await loadEntries(workflow: workflow, jobId: jobId);
    final index = entries.indexWhere((item) => item.entryId == entry.entryId);
    final next = entry.copyWith(lastModifiedAt: DateTime.now());
    if (index >= 0) {
      entries[index] = next;
    } else {
      entries.add(next);
    }
    await saveEntries(workflow: workflow, jobId: jobId, entries: entries);
  }

  Future<void> deleteEntry({
    required OperationsLogWorkflow workflow,
    required String jobId,
    required String entryId,
  }) async {
    final entries = await loadEntries(workflow: workflow, jobId: jobId);
    final removed = entries
        .where((entry) => entry.entryId == entryId)
        .toList(growable: false);
    for (final entry in removed) {
      await _stsReminderService.cancelForEntry(
        entry,
        reason: 'entryDeleted',
      );
    }
    entries.removeWhere((entry) => entry.entryId == entryId);
    await saveEntries(workflow: workflow, jobId: jobId, entries: entries);
  }

  Future<ExportedOperationsLogReportFile> exportShiftReportPdf({
    required OperationsLogWorkflow workflow,
    required String jobName,
    required String wellName,
    required String stage,
    required List<OperationsLogEntry> entries,
    Set<String>? enabledFieldIds,
    String? baseFileName,
  }) async {
    final pdfBytes = await buildShiftReportPdfBytes(
      workflow: workflow,
      jobName: jobName,
      wellName: wellName,
      stage: stage,
      entries: entries,
      enabledFieldIds: enabledFieldIds,
    );
    final fileName = _buildReportFileName(
      workflow: workflow,
      baseFileName: baseFileName,
    );
    final directory = await _ensureExportDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pdfBytes, flush: true);
    return ExportedOperationsLogReportFile(
      filePath: file.path,
      fileName: fileName,
    );
  }

  Future<Uint8List> buildShiftReportPdfBytes({
    required OperationsLogWorkflow workflow,
    required String jobName,
    required String wellName,
    required String stage,
    required List<OperationsLogEntry> entries,
    Set<String>? enabledFieldIds,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final profile = await _operatorProfileService.load();
    final sortedEntries = List<OperationsLogEntry>.from(entries)
      ..sort((a, b) => a.readingTimestamp.compareTo(b.readingTimestamp));
    final visibleFieldIds = (enabledFieldIds ??
            DrilloutCleanoutFieldDefinitions.defaultEnabledFieldIds)
        .toSet();
    final readingColumns = _buildReadingColumns(visibleFieldIds, sortedEntries);
    final stamp = DateTime.now();
    final doc = pw.Document(compress: false);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
        header: (context) => _reportHeader(
          workflow: workflow,
          jobName: jobName,
          wellName: wellName,
          stage: stage,
          entries: sortedEntries,
          generatedAt: stamp,
          profile: profile,
          buildNumber: packageInfo.buildNumber,
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 10),
          _sectionTitle('Summary'),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.7),
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(1.3),
              1: pw.FlexColumnWidth(2.7),
            },
            children: [
              _summaryRow('Workflow', _workflowLabel(workflow)),
              _summaryRow('Job', jobName),
              _summaryRow('Well', wellName),
              _summaryRow('Stage', stage),
              _summaryRow('Readings', sortedEntries.length.toString()),
              _summaryRow(
                'Latest status per well',
                _latestStatusByWellSummary(sortedEntries),
              ),
              _summaryRow(
                'Generated',
                DateFormat('MMM d, yyyy h:mm a').format(stamp),
              ),
              _summaryRow('Prepared by', _preparedBy(profile)),
              _summaryRow('Build', packageInfo.buildNumber),
            ],
          ),
          pw.SizedBox(height: 12),
          _sectionTitle('Readings'),
          if (sortedEntries.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line, width: 0.7),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'No readings were recorded for this log.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: _line, width: 0.7),
              columnWidths: {
                0: const pw.FixedColumnWidth(56),
                1: const pw.FlexColumnWidth(1.4),
                for (var i = 0; i < readingColumns.length; i++)
                  i + 2: readingColumns[i].width,
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF5F7FA),
                  ),
                  children: [
                    _tableHeaderCell('Time'),
                    _tableHeaderCell('Well'),
                    for (final column in readingColumns)
                      _tableHeaderCell(column.label),
                  ],
                ),
                for (final entry in sortedEntries)
                  pw.TableRow(
                    children: [
                      _tableCell(DateFormat('h:mm a')
                          .format(entry.readingTimestamp.toLocal())),
                      _tableCell(entry.wellName),
                      for (final column in readingColumns)
                        _tableCell(column.valueBuilder(entry)),
                    ],
                  ),
              ],
            ),
          pw.SizedBox(height: 12),
          _sectionTitle('Notes'),
          pw.Text(
            'This compact report is generated from the local operations log. QR sharing remains available for full reading transfer.',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<OperationsLogPackage> buildPackage({
    required OperationsLogPackageType packageType,
    required String persistentJobId,
    required List<OperationsLogEntry> entries,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final profile = await _operatorProfileService.load();
    final deviceId = await _deviceIdentityService.load();
    final packageId = _newId('operations');
    return OperationsLogPackage(
      fileType: _packageFileType,
      schemaVersion: _schemaVersion,
      packageType: packageType.value,
      packageId: packageId,
      createdAt: DateTime.now().toIso8601String(),
      sourceBuildNumber: packageInfo.buildNumber,
      sourceOperatorId: profile.operatorId,
      sourceOperatorName: profile.name,
      sourceOperatorInitials: profile.initials,
      sourceDeviceId: deviceId,
      persistentJobId: persistentJobId.trim(),
      workflow: packageType.workflow.name,
      entries: List<OperationsLogEntry>.from(entries),
    );
  }

  String encodePackage(OperationsLogPackage package) {
    return _qrTransferService
        .encodeStructuredPayload(jsonEncode(package.toJson()));
  }

  OperationsLogPackage decodePackage(String rawValue) {
    final rawJson = _qrTransferService.decodeStructuredPayload(rawValue);
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid operations log package.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final fileType = (map['fileType'] as String? ?? '').trim();
    final schemaVersion = (map['schemaVersion'] as String? ?? '').trim();
    if (fileType != _packageFileType) {
      throw const FormatException('Unsupported operations log package type.');
    }
    if (schemaVersion != _schemaVersion) {
      throw const FormatException('Unsupported operations log schema version.');
    }
    return OperationsLogPackage.fromJson(map);
  }

  Future<OperationsLogImportResult> importEntries({
    required OperationsLogWorkflow workflow,
    required String jobId,
    required OperationsLogPackage package,
    required List<OperationsLogEntry> existingEntries,
  }) async {
    if (package.workflow.trim() != workflow.name) {
      throw FormatException(
        workflow == OperationsLogWorkflow.drillout
            ? 'This is a Cleanout reading. Open Import Reading from the Cleanout Log.'
            : 'This is a Drillout reading. Open Import Reading from the Drillout Log.',
      );
    }
    if (package.persistentJobId.trim().isNotEmpty &&
        package.persistentJobId.trim() != jobId.trim()) {
      throw const FormatException(
        'The matching job is not on this device. Import or create the Job Setup before adding these readings.',
      );
    }

    final existingById = <String, OperationsLogEntry>{
      for (final entry in existingEntries) entry.entryId: entry,
    };
    final added = <OperationsLogEntry>[];
    final duplicates = <OperationsLogDuplicate>[];
    final conflicts = <OperationsLogConflict>[];

    for (final incoming in package.entries) {
      final existing = existingById[incoming.entryId];
      if (existing == null) {
        final next = incoming.copyWith(
          isImported: true,
          importedAt: DateTime.now(),
          qrPackageId: package.packageId,
          sourceBuildNumber: package.sourceBuildNumber,
          sourceOperatorId: package.sourceOperatorId,
          sourceOperatorName: package.sourceOperatorName,
          sourceOperatorInitials: package.sourceOperatorInitials,
          sourceDeviceId: package.sourceDeviceId,
        );
        added.add(next);
        continue;
      }
      if (_sameEntry(existing, incoming)) {
        duplicates.add(OperationsLogDuplicate(entry: existing));
      } else {
        conflicts
            .add(OperationsLogConflict(existing: existing, incoming: incoming));
      }
    }

    final merged = [...existingEntries, ...added]
      ..sort((a, b) => a.readingTimestamp.compareTo(b.readingTimestamp));
    await saveEntries(workflow: workflow, jobId: jobId, entries: merged);
    await _appendHistory(package: package, imported: added.length);
    return OperationsLogImportResult(
      added: added,
      duplicates: duplicates,
      conflicts: conflicts,
    );
  }

  Future<void> _appendHistory({
    required OperationsLogPackage package,
    required int imported,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? <String>[];
    history.insert(
      0,
      jsonEncode(<String, dynamic>{
        'packageId': package.packageId,
        'packageType': package.packageType,
        'workflow': package.workflow,
        'jobId': package.persistentJobId,
        'createdAt': package.createdAt,
        'imported': imported,
        'entryIds': package.entries.map((entry) => entry.entryId).toList(),
      }),
    );
    await prefs.setStringList(_historyKey, history.take(200).toList());
  }

  bool _sameEntry(OperationsLogEntry a, OperationsLogEntry b) {
    return a.toJson().toString() == b.toJson().toString();
  }

  Future<Directory> _ensureExportDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory =
        Directory('${root.path}/wellwerks_operations_log_exports');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _buildReportFileName({
    required OperationsLogWorkflow workflow,
    String? baseFileName,
  }) {
    final base = baseFileName?.trim().isNotEmpty == true
        ? baseFileName!.trim()
        : '${workflow.name}_shift_report';
    final safeBase = base
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${safeBase.isEmpty ? 'operations_shift_report' : safeBase}.pdf';
  }

  pw.Widget _reportHeader({
    required OperationsLogWorkflow workflow,
    required String jobName,
    required String wellName,
    required String stage,
    required List<OperationsLogEntry> entries,
    required DateTime generatedAt,
    required OperatorProfile profile,
    required String buildNumber,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${_workflowLabel(workflow)} Shift Report',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: _gold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            jobName.trim().isEmpty
                ? 'WellWerks operations log'
                : jobName.trim(),
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated ${DateFormat('MMM d, yyyy h:mm a').format(generatedAt)} by ${_preparedBy(profile)} | Build $buildNumber',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          if (wellName.trim().isNotEmpty || stage.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                [
                  if (wellName.trim().isNotEmpty) 'Well ${wellName.trim()}',
                  if (stage.trim().isNotEmpty) 'Stage ${stage.trim()}',
                  '${entries.length} readings',
                ].join(' | '),
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );
  }

  pw.TableRow _summaryRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            value.trim().isEmpty ? '-' : value.trim(),
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: _gold,
        ),
      ),
    );
  }

  pw.Widget _tableHeaderCell(String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  pw.Widget _tableCell(String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        value.trim().isEmpty ? '-' : value.trim(),
        style: const pw.TextStyle(fontSize: 8.5),
      ),
    );
  }

  List<_ReadingReportColumn> _buildReadingColumns(
    Set<String> enabledFieldIds,
    List<OperationsLogEntry> entries,
  ) {
    final columns = <_ReadingReportColumn>[];

    for (final field in DrilloutCleanoutFieldDefinitions.readingFields) {
      final legacySweepPresent =
          field.id == DrilloutCleanoutFieldDefinitions.sweepInformationId &&
              entries.any((entry) => entry.sweepInformation.trim().isNotEmpty);
      if ((!enabledFieldIds.contains(field.id) && !legacySweepPresent) ||
          !field.reportVisible) {
        continue;
      }
      if (!entries
          .any((entry) => _reportValueForField(field.id, entry).isNotEmpty)) {
        continue;
      }
      columns.add(
        _ReadingReportColumn(
          label: field.label,
          width: _reportWidthForField(field.id),
          valueBuilder: (entry) => _reportValueForField(field.id, entry),
        ),
      );
    }

    if (columns.isEmpty) {
      columns.add(
        _ReadingReportColumn(
          label: 'Notes',
          width: const pw.FlexColumnWidth(1.6),
          valueBuilder: (entry) => entry.notes,
        ),
      );
    }

    return columns;
  }

  pw.TableColumnWidth _reportWidthForField(String fieldId) {
    switch (fieldId) {
      case 'operationStage':
        return const pw.FlexColumnWidth(1.2);
      case 'pumpRate':
      case 'returnsRate':
      case 'casingPressure':
      case 'pumpPressure':
      case 'tubingPressure':
      case 'choke':
      case 'gas':
      case 'sandOrSolids':
      case 'plugNumber':
      case 'surfaceTotalFluid':
      case 'waterHauled':
      case 'oilHauled':
        return const pw.FlexColumnWidth(0.9);
      case 'estimatedSts':
      case 'sts':
      case 'sweepInformation':
      case 'equipmentStatus':
      case 'downtime':
      case 'tankLevel':
        return const pw.FlexColumnWidth(1.2);
      case 'notes':
        return const pw.FlexColumnWidth(1.6);
      default:
        return const pw.FlexColumnWidth(1.0);
    }
  }

  String _reportValueForField(String fieldId, OperationsLogEntry entry) {
    switch (fieldId) {
      case 'operationStage':
        return entry.operationStage.trim();
      case 'pumpRate':
        return entry.pumpRate.trim();
      case 'returnsRate':
        return entry.returnsRate.trim();
      case 'tubingPressure':
        return entry.tubingPressure.trim();
      case 'casingPressure':
        return entry.casingPressure.trim();
      case 'pumpPressure':
        return entry.pumpPressure.trim();
      case 'gas':
        return entry.gas.trim();
      case 'estimatedSts':
        return _formatReportDateTime(entry.estimatedSts);
      case 'sts':
        return _formatReportDateTime(entry.sts);
      case 'sandOrSolids':
        return entry.sandOrSolids.trim();
      case 'plugNumber':
        return entry.plugNumber.trim();
      case 'surfaceTotalFluid':
        return entry.surfaceTotalFluid.trim();
      case 'waterHauled':
        return entry.waterHauled.trim();
      case 'oilHauled':
        return entry.oilHauled.trim();
      case 'sweepInformation':
        return entry.sweepInformation.trim();
      case 'tankLevel':
        return entry.tankLevel.trim();
      case 'choke':
        return entry.choke.trim();
      case 'equipmentStatus':
        return entry.equipmentStatus.trim();
      case 'downtime':
        return entry.downtime.trim();
      case 'notes':
        return entry.notes.trim();
      default:
        return '';
    }
  }

  String _formatReportDateTime(DateTime? value) {
    if (value == null) return '';
    return DateFormat('M/d h:mm a').format(value.toLocal());
  }

  String _latestStatusByWellSummary(List<OperationsLogEntry> sortedEntries) {
    if (sortedEntries.isEmpty) return '-';
    final latestByWell = <String, String>{};
    for (final entry in sortedEntries) {
      final well = entry.wellName.trim();
      if (well.isEmpty) continue;
      final status = entry.operationStage.trim();
      if (status.isNotEmpty) {
        latestByWell[well] = status;
      }
    }
    if (latestByWell.isEmpty) return '-';
    return latestByWell.entries
        .map((item) => '${item.key}: ${item.value}')
        .join(' | ');
  }

  String _workflowLabel(OperationsLogWorkflow workflow) {
    return workflow == OperationsLogWorkflow.drillout ? 'Drillout' : 'Cleanout';
  }

  String _preparedBy(OperatorProfile profile) {
    final name = profile.name.trim();
    final initials = profile.initials.trim();
    if (name.isEmpty && initials.isEmpty) return 'Local operator';
    if (name.isEmpty) return initials;
    if (initials.isEmpty) return name;
    return '$name ($initials)';
  }

  String _newId(String prefix) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${prefix}_$stamp';
  }
}

class _ReadingReportColumn {
  const _ReadingReportColumn({
    required this.label,
    required this.width,
    required this.valueBuilder,
  });

  final String label;
  final pw.TableColumnWidth width;
  final String Function(OperationsLogEntry entry) valueBuilder;
}
