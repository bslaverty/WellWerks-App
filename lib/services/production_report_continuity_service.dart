import 'package:intl/intl.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../utils/production_day.dart';

class ProductionReportContinuityService {
  const ProductionReportContinuityService();

  List<ProductionReportRow> normalizedRowsForJob({
    required ProductionShift shift,
    JobSetup? activeJob,
    DateTime? now,
  }) {
    final sourceRows = shift.inventory.productionRows.isNotEmpty
        ? shift.inventory.productionRows
        : shift.savedRows;
    final referenceDate = _resolveReferenceDate(shift, now: now);
    final activeJobId = activeJob?.id.trim() ?? '';
    final jobId =
        activeJobId.isNotEmpty ? activeJobId : shift.activeJobId.trim();
    final jobWells = activeJob?.wellEntries ?? const <JobSetupWell>[];

    return sourceRows.map((row) {
      final timestamp = _resolvedTimestampForRow(row, referenceDate);
      final timestampIso = timestamp.toIso8601String();
      final mappedWellId = _wellIdForName(row.well, jobWells);
      final wellId = mappedWellId.isNotEmpty ? mappedWellId : row.wellId.trim();
      final entryId = row.entryId.trim().isNotEmpty
          ? row.entryId.trim()
          : _buildStableEntryId(
              jobId: jobId,
              row: row,
              timestampIso: timestampIso,
              wellId: wellId,
            );
      final createdAt = row.createdAtIso.trim().isNotEmpty
          ? row.createdAtIso.trim()
          : timestampIso;
      final lastModified = row.lastModifiedAtIso.trim().isNotEmpty
          ? row.lastModifiedAtIso.trim()
          : createdAt;
      final productionDay = row.productionDay.trim().isNotEmpty
          ? row.productionDay.trim()
          : productionDayKey(timestamp);

      return row.copyWithMetadata(
        entryId: entryId,
        activeJobId: jobId,
        wellId: wellId,
        originalTimestampIso: row.originalTimestampIso.trim().isNotEmpty
            ? row.originalTimestampIso.trim()
            : timestampIso,
        productionDay: productionDay,
        createdAtIso: createdAt,
        lastModifiedAtIso: lastModified,
        sourceDeviceId: row.sourceDeviceId.trim().isEmpty
            ? 'local'
            : row.sourceDeviceId.trim(),
        sourceHandoffId: row.sourceHandoffId.trim(),
      );
    }).toList(growable: false);
  }

  Map<String, List<ProductionReportRow>> groupByProductionDay(
    List<ProductionReportRow> rows,
  ) {
    final grouped = <String, List<ProductionReportRow>>{};
    for (final row in rows) {
      final key = row.productionDay.trim();
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => <ProductionReportRow>[]).add(row);
    }

    for (final dayRows in grouped.values) {
      dayRows.sort((a, b) {
        final aStamp = DateTime.tryParse(a.originalTimestampIso);
        final bStamp = DateTime.tryParse(b.originalTimestampIso);
        if (aStamp != null && bStamp != null) {
          final compare = aStamp.compareTo(bStamp);
          if (compare != 0) return compare;
        }
        return a.hourIndex.compareTo(b.hourIndex);
      });
    }
    return grouped;
  }

  DateTime _resolveReferenceDate(ProductionShift shift, {DateTime? now}) {
    final raw = shift.header.date.trim();
    final parsed = _parseDate(raw);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final localNow = (now ?? DateTime.now()).toLocal();
    return DateTime(localNow.year, localNow.month, localNow.day);
  }

  DateTime? _parseDate(String raw) {
    if (raw.trim().isEmpty) return null;
    const patterns = [
      'yyyy-MM-dd',
      'MM/dd/yyyy',
      'M/d/yyyy',
      'MMM d, yyyy',
    ];
    for (final pattern in patterns) {
      try {
        return DateFormat(pattern).parseStrict(raw);
      } catch (_) {
        // Try next.
      }
    }
    return null;
  }

  DateTime _resolvedTimestampForRow(ProductionReportRow row, DateTime baseDay) {
    final existing = DateTime.tryParse(row.originalTimestampIso.trim());
    if (existing != null) return existing.toLocal();

    final parsedTime = _parseTime(row.time);
    final hour = parsedTime?.hour ?? row.hourIndex;
    final minute = parsedTime?.minute ?? 0;

    const rolloverHour = 6;
    final offsetDays = hour < rolloverHour ? 1 : 0;
    final local = DateTime(
      baseDay.year,
      baseDay.month,
      baseDay.day + offsetDays,
      hour,
      minute,
    );
    return local;
  }

  DateTime? _parseTime(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    const formats = [
      'h a',
      'h:mm a',
      'hh:mm a',
      'H:mm',
      'HH:mm',
    ];
    for (final format in formats) {
      try {
        return DateFormat(format).parseStrict(text);
      } catch (_) {
        // Try next.
      }
    }
    return null;
  }

  String _wellIdForName(String wellName, List<JobSetupWell> wells) {
    final trimmed = wellName.trim().toLowerCase();
    for (final item in wells) {
      if (item.name.trim().toLowerCase() == trimmed) {
        return item.id.trim();
      }
    }
    return '';
  }

  String _buildStableEntryId({
    required String jobId,
    required ProductionReportRow row,
    required String timestampIso,
    required String wellId,
  }) {
    final wellKey = wellId.trim().isEmpty ? row.well.trim() : wellId.trim();
    return [
      'entry',
      jobId.isEmpty ? 'unbound' : jobId,
      timestampIso,
      wellKey.isEmpty ? 'well' : wellKey,
      row.hourIndex.toString(),
    ].join('|');
  }
}
