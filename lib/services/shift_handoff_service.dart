import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import 'production_report_continuity_service.dart';

class ShiftHandoffConflict {
  const ShiftHandoffConflict({
    required this.entryId,
    required this.local,
    required this.imported,
  });

  final String entryId;
  final ProductionReportRow local;
  final ProductionReportRow imported;
}

class ShiftHandoffMergeResult {
  const ShiftHandoffMergeResult({
    required this.mergedShift,
    required this.entriesAdded,
    required this.duplicatesSkipped,
    required this.conflicts,
    required this.jobIdMismatch,
  });

  final ProductionShift mergedShift;
  final int entriesAdded;
  final int duplicatesSkipped;
  final List<ShiftHandoffConflict> conflicts;
  final bool jobIdMismatch;
}

class ShiftHandoffPackage {
  const ShiftHandoffPackage({
    required this.fileType,
    required this.schemaVersion,
    required this.appVersion,
    required this.buildNumber,
    required this.handoffId,
    required this.exportedAt,
    required this.sourceJobId,
    required this.jobType,
    required this.customer,
    required this.jobName,
    required this.productionShift,
    required this.productionRows,
  });

  final String fileType;
  final String schemaVersion;
  final String appVersion;
  final String buildNumber;
  final String handoffId;
  final String exportedAt;
  final String sourceJobId;
  final String jobType;
  final String customer;
  final String jobName;
  final Map<String, dynamic> productionShift;
  final List<Map<String, dynamic>> productionRows;

  Map<String, dynamic> toJson() {
    return {
      'fileType': fileType,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'handoffId': handoffId,
      'exportedAt': exportedAt,
      'sourceJobId': sourceJobId,
      'jobType': jobType,
      'customer': customer,
      'jobName': jobName,
      'productionShift': productionShift,
      'productionRows': productionRows,
    };
  }

  factory ShiftHandoffPackage.fromJson(Map<String, dynamic> json) {
    return ShiftHandoffPackage(
      fileType: json['fileType'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      buildNumber: json['buildNumber'] as String? ?? '',
      handoffId: json['handoffId'] as String? ?? '',
      exportedAt: json['exportedAt'] as String? ?? '',
      sourceJobId: json['sourceJobId'] as String? ?? '',
      jobType: json['jobType'] as String? ?? '',
      customer: json['customer'] as String? ?? '',
      jobName: json['jobName'] as String? ?? '',
      productionShift:
          Map<String, dynamic>.from((json['productionShift'] as Map?) ?? {}),
      productionRows: ((json['productionRows'] as List?) ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false),
    );
  }
}

class ShiftHandoffService {
  ShiftHandoffService({
    ProductionReportContinuityService? continuity,
  }) : _continuity = continuity ?? const ProductionReportContinuityService();

  static const currentSchemaVersion = '1.0.0';
  static const currentFileType = 'wellwerks_shift_handoff';

  final ProductionReportContinuityService _continuity;

  Future<ShiftHandoffPackage> buildPackage({
    required ProductionShift shift,
    required JobSetup? activeJob,
    String? handoffId,
    DateTime? now,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final stamp = now ?? DateTime.now();

    final normalized = _continuity.normalizedRowsForJob(
      shift: shift,
      activeJob: activeJob,
      now: stamp,
    );
    final normalizedShift = shift.copyWith(
      savedRows: normalized,
      inventory: shift.inventory.copyWith(productionRows: normalized),
    );
    final activeJobId = activeJob?.id.trim() ?? '';
    final sourceJobId =
        activeJobId.isNotEmpty ? activeJobId : shift.activeJobId.trim();

    return ShiftHandoffPackage(
      fileType: currentFileType,
      schemaVersion: currentSchemaVersion,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      handoffId:
          handoffId ?? 'handoff_${stamp.microsecondsSinceEpoch}_$sourceJobId',
      exportedAt: stamp.toIso8601String(),
      sourceJobId: sourceJobId,
      jobType: activeJob?.jobType ?? '',
      customer: activeJob?.company ?? shift.header.company,
      jobName: activeJob?.padName ?? shift.header.pad,
      productionShift: normalizedShift.toJson(),
      productionRows: normalized.map((row) => row.toJson()).toList(),
    );
  }

  String encodePackage(ShiftHandoffPackage package) {
    return jsonEncode(package.toJson());
  }

  ShiftHandoffPackage decodePackage(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid handoff file format.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final fileType = map['fileType'] as String? ?? '';
    if (fileType != currentFileType) {
      throw const FormatException('Unsupported handoff file type.');
    }
    final schemaVersion = map['schemaVersion'] as String? ?? '';
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported handoff schema version.');
    }
    return ShiftHandoffPackage.fromJson(map);
  }

  ShiftHandoffMergeResult mergePackage({
    required ProductionShift localShift,
    required JobSetup? activeJob,
    required ShiftHandoffPackage package,
    bool allowJobIdMismatch = false,
  }) {
    final localJobId = (activeJob?.id ?? localShift.activeJobId).trim();
    final sourceJobId = package.sourceJobId.trim();
    if (!allowJobIdMismatch &&
        localJobId.isNotEmpty &&
        sourceJobId.isNotEmpty &&
        sourceJobId != localJobId) {
      return ShiftHandoffMergeResult(
        mergedShift: localShift,
        entriesAdded: 0,
        duplicatesSkipped: 0,
        conflicts: const <ShiftHandoffConflict>[],
        jobIdMismatch: true,
      );
    }

    final localRows = _continuity.normalizedRowsForJob(
      shift: localShift,
      activeJob: activeJob,
    );
    final importedShift = ProductionShift.fromJson(package.productionShift);
    final rawImportedRows = package.productionRows.isNotEmpty
        ? package.productionRows
            .map(ProductionReportRow.fromJson)
            .toList(growable: false)
        : (importedShift.inventory.productionRows.isNotEmpty
            ? importedShift.inventory.productionRows
            : importedShift.savedRows);
    final importedShiftWithRows = importedShift.copyWith(
      savedRows: rawImportedRows,
      inventory:
          importedShift.inventory.copyWith(productionRows: rawImportedRows),
    );
    final importedRows = _continuity.normalizedRowsForJob(
      shift: importedShiftWithRows,
      activeJob: null,
    );

    final byId = <String, ProductionReportRow>{
      for (final row in localRows)
        if (row.entryId.trim().isNotEmpty) row.entryId.trim(): row,
    };

    var added = 0;
    var skipped = 0;
    final conflicts = <ShiftHandoffConflict>[];

    for (final incoming in importedRows) {
      final id = incoming.entryId.trim();
      if (id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = incoming;
        added++;
        continue;
      }
      if (jsonEncode(existing.toJson()) == jsonEncode(incoming.toJson())) {
        skipped++;
        continue;
      }
      conflicts.add(
        ShiftHandoffConflict(
          entryId: id,
          local: existing,
          imported: incoming,
        ),
      );
    }

    final mergedRows = byId.values.toList(growable: false)
      ..sort((a, b) {
        final aTs = DateTime.tryParse(a.originalTimestampIso);
        final bTs = DateTime.tryParse(b.originalTimestampIso);
        if (aTs != null && bTs != null) {
          final compare = aTs.compareTo(bTs);
          if (compare != 0) return compare;
        }
        return a.hourIndex.compareTo(b.hourIndex);
      });

    final mergedShift = localShift.copyWith(
      savedRows: mergedRows,
      inventory: localShift.inventory.copyWith(productionRows: mergedRows),
    );

    return ShiftHandoffMergeResult(
      mergedShift: mergedShift,
      entriesAdded: added,
      duplicatesSkipped: skipped,
      conflicts: conflicts,
      jobIdMismatch: false,
    );
  }

  ProductionShift applyConflictResolutions({
    required ShiftHandoffMergeResult mergeResult,
    required Set<String> preferImportedEntryIds,
  }) {
    final byId = <String, ProductionReportRow>{
      for (final row in mergeResult.mergedShift.savedRows)
        if (row.entryId.trim().isNotEmpty) row.entryId.trim(): row,
    };

    for (final conflict in mergeResult.conflicts) {
      final id = conflict.entryId.trim();
      if (id.isEmpty) continue;
      byId[id] = preferImportedEntryIds.contains(id)
          ? conflict.imported
          : conflict.local;
    }

    final resolvedRows = byId.values.toList(growable: false)
      ..sort((a, b) {
        final aTs = DateTime.tryParse(a.originalTimestampIso);
        final bTs = DateTime.tryParse(b.originalTimestampIso);
        if (aTs != null && bTs != null) {
          final compare = aTs.compareTo(bTs);
          if (compare != 0) return compare;
        }
        return a.hourIndex.compareTo(b.hourIndex);
      });

    return mergeResult.mergedShift.copyWith(
      savedRows: resolvedRows,
      inventory: mergeResult.mergedShift.inventory.copyWith(
        productionRows: resolvedRows,
      ),
    );
  }
}
