import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/models/production_shift.dart';
import 'package:wellwerks/services/production_report_continuity_service.dart';
import 'package:wellwerks/services/shift_handoff_service.dart';

ProductionReportRow _row({
  required String id,
  required int hour,
  required String time,
  required String well,
  required String timestampIso,
  required String productionDay,
  String notes = '',
  double water = 10,
  double oil = 20,
  double gas = 30,
}) {
  return ProductionReportRow(
    hourIndex: hour,
    time: time,
    well: well,
    choke: '28',
    chokeType: 'ADJ',
    tbg: '1000',
    csg: '800',
    waterProduction: water,
    oilProduction: oil,
    hourlyGas: gas,
    gas24HourRate: gas * 24,
    gasStatic: '100',
    gasDifferential: '10',
    gasTemp: '70',
    sandRate: '.2',
    waterGaugeText: 'Water Tank 1: 30 in',
    oilGaugeText: 'Oil Tank 1: 20 in',
    currentWaterBbl: 100,
    currentOilBbl: 80,
    currentGasAccum: 1000,
    waterHauled: 0,
    oilHauled: 0,
    waterPumped: 0,
    oilPumped: 0,
    notes: notes,
    entryId: id,
    activeJobId: 'job-1',
    wellId: 'well-1',
    originalTimestampIso: timestampIso,
    productionDay: productionDay,
    createdAtIso: timestampIso,
    lastModifiedAtIso: timestampIso,
    sourceDeviceId: 'device-a',
  );
}

ProductionShift _shiftWithRows(List<ProductionReportRow> rows,
    {String jobId = 'job-1'}) {
  return ProductionShift.empty().copyWith(
    activeJobId: jobId,
    header: const ProductionShiftHeader(
      company: 'Mach Energy',
      pad: 'Horse Pad',
      date: '2026-07-27',
      wells: ['Horse 16-2H'],
    ),
    savedRows: rows,
    inventory:
        ProductionInventoryBaseline.empty().copyWith(productionRows: rows),
  );
}

void main() {
  const continuity = ProductionReportContinuityService();
  final handoff = ShiftHandoffService(continuity: continuity);

  test('Build 182 merge imports new entries', () {
    final local = _shiftWithRows([
      _row(
        id: 'entry-1',
        hour: 6,
        time: '6:00 AM',
        well: 'Horse 16-2H',
        timestampIso: DateTime(2026, 7, 27, 6).toIso8601String(),
        productionDay: '2026-07-27',
      ),
    ]);

    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.0',
      buildNumber: '182',
      handoffId: 'handoff-1',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [
        _row(
          id: 'entry-2',
          hour: 7,
          time: '7:00 AM',
          well: 'Horse 16-2H',
          timestampIso: DateTime(2026, 7, 27, 7).toIso8601String(),
          productionDay: '2026-07-27',
        ).toJson(),
      ],
    );

    final merged = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
          company: 'Mach', padName: 'Horse Pad', wells: const ['Horse 16-2H']),
      package: package,
    );

    expect(merged.entriesAdded, 1);
    expect(merged.duplicatesSkipped, 0);
    expect(merged.conflicts, isEmpty);
    expect(merged.mergedShift.savedRows.length, 2);
  });

  test('Build 182 merge skips identical duplicate entries', () {
    final shared = _row(
      id: 'entry-1',
      hour: 6,
      time: '6:00 AM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 6).toIso8601String(),
      productionDay: '2026-07-27',
    );
    final local = _shiftWithRows([shared]);

    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.0',
      buildNumber: '182',
      handoffId: 'handoff-2',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [shared.toJson()],
    );

    final merged = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
          company: 'Mach', padName: 'Horse Pad', wells: const ['Horse 16-2H']),
      package: package,
    );

    expect(merged.entriesAdded, 0);
    expect(merged.duplicatesSkipped, 1);
    expect(merged.mergedShift.savedRows.length, 1);
  });

  test('Build 182 importing same handoff twice creates no duplicates', () {
    final local = _shiftWithRows([]);
    final newRow = _row(
      id: 'entry-3',
      hour: 8,
      time: '8:00 AM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 8).toIso8601String(),
      productionDay: '2026-07-27',
    );

    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.0',
      buildNumber: '182',
      handoffId: 'handoff-3',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [newRow.toJson()],
    );

    final once = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
          company: 'Mach', padName: 'Horse Pad', wells: const ['Horse 16-2H']),
      package: package,
    );
    final twice = handoff.mergePackage(
      localShift: once.mergedShift,
      activeJob: JobSetup(
          company: 'Mach', padName: 'Horse Pad', wells: const ['Horse 16-2H']),
      package: package,
    );

    expect(once.entriesAdded, 1);
    expect(twice.entriesAdded, 0);
    expect(twice.duplicatesSkipped, 1);
    expect(twice.mergedShift.savedRows.length, 1);
  });

  test('Build 182 same entry id with different content creates conflict', () {
    final localRow = _row(
      id: 'entry-4',
      hour: 9,
      time: '9:00 AM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 9).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'local',
    );
    final importedRow = _row(
      id: 'entry-4',
      hour: 9,
      time: '9:00 AM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 9).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'imported',
    );

    final local = _shiftWithRows([localRow]);
    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.0',
      buildNumber: '182',
      handoffId: 'handoff-4',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [importedRow.toJson()],
    );

    final merged = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
          company: 'Mach', padName: 'Horse Pad', wells: const ['Horse 16-2H']),
      package: package,
    );

    expect(merged.entriesAdded, 0);
    expect(merged.conflicts.length, 1);
    expect(merged.mergedShift.savedRows.single.notes, 'local');
  });

  test('Build 182 rows group by production day including before 6 AM', () {
    final rows = [
      _row(
        id: 'entry-5',
        hour: 23,
        time: '11:00 PM',
        well: 'Horse 16-2H',
        timestampIso: DateTime(2026, 7, 27, 23).toIso8601String(),
        productionDay: '2026-07-27',
      ),
      _row(
        id: 'entry-6',
        hour: 2,
        time: '2:00 AM',
        well: 'Horse 16-2H',
        timestampIso: DateTime(2026, 7, 28, 2).toIso8601String(),
        productionDay: '2026-07-27',
      ),
      _row(
        id: 'entry-7',
        hour: 6,
        time: '6:00 AM',
        well: 'Horse 16-2H',
        timestampIso: DateTime(2026, 7, 28, 6).toIso8601String(),
        productionDay: '2026-07-28',
      ),
    ];
    final grouped = continuity.groupByProductionDay(rows);
    expect(grouped['2026-07-27']?.length, 2);
    expect(grouped['2026-07-28']?.length, 1);
  });

  test('Build 182 local newer data is not silently overwritten', () {
    final localRow = _row(
      id: 'entry-8',
      hour: 10,
      time: '10:00 AM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 10).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'newer-local',
    ).copyWithMetadata(
        lastModifiedAtIso: DateTime(2026, 7, 27, 11).toIso8601String());

    final importedRow = _row(
      id: 'entry-8',
      hour: 10,
      time: '10:00 AM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 10).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'older-import',
    ).copyWithMetadata(
        lastModifiedAtIso: DateTime(2026, 7, 27, 10, 30).toIso8601String());

    final local = _shiftWithRows([localRow]);
    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.0',
      buildNumber: '182',
      handoffId: 'handoff-5',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [importedRow.toJson()],
    );

    final merged = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
          company: 'Mach', padName: 'Horse Pad', wells: const ['Horse 16-2H']),
      package: package,
    );

    expect(merged.conflicts.length, 1);
    expect(merged.mergedShift.savedRows.single.notes, 'newer-local');
  });

  test('Build 182 imported job id mismatch does not auto merge', () {
    final local = _shiftWithRows([], jobId: 'job-local');
    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.0',
      buildNumber: '182',
      handoffId: 'handoff-6',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-remote',
      jobType: 'production',
      customer: 'Mach',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [
        _row(
          id: 'entry-9',
          hour: 11,
          time: '11:00 AM',
          well: 'Horse 16-2H',
          timestampIso: DateTime(2026, 7, 27, 11).toIso8601String(),
          productionDay: '2026-07-27',
        ).toJson(),
      ],
    );

    final merged = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
        id: 'job-local',
        company: 'Mach',
        padName: 'Horse Pad',
        wells: const ['Horse 16-2H'],
      ),
      package: package,
    );

    expect(merged.jobIdMismatch, isTrue);
    expect(merged.entriesAdded, 0);
    expect(merged.mergedShift.savedRows, isEmpty);
  });

  test('Build 182 handoff package roundtrip preserves metadata and values', () {
    final row = _row(
      id: 'entry-10',
      hour: 12,
      time: '12:00 PM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 12).toIso8601String(),
      productionDay: '2026-07-27',
      water: 42,
      oil: 55,
      gas: 90,
    );
    final shift = _shiftWithRows([row]);

    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.1',
      buildNumber: '182',
      handoffId: 'handoff-7',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach Energy',
      jobName: 'Horse Pad',
      productionShift: shift.toJson(),
      productionRows: [row.toJson()],
    );

    final raw = handoff.encodePackage(package);
    final decoded = handoff.decodePackage(raw);

    expect(decoded.handoffId, 'handoff-7');
    expect(decoded.sourceJobId, 'job-1');
    expect(decoded.productionRows.single['entryId'], 'entry-10');
    expect(decoded.productionRows.single['waterProduction'], 42.0);
    expect(decoded.productionRows.single['oilProduction'], 55.0);

    final decodedShift = ProductionShift.fromJson(decoded.productionShift);
    expect(decodedShift.inventory.productionRows.length, 1);
    expect(decodedShift.inventory.productionRows.single.currentWaterBbl, 100);
  });

  test('Build 182 unsupported schema is rejected safely', () {
    const raw =
        '{"fileType":"wellwerks_shift_handoff","schemaVersion":"9.9.9"}';
    expect(
      () => handoff.decodePackage(raw),
      throwsFormatException,
    );
  });

  test('Build 182 corrupt handoff data is rejected safely', () {
    expect(
      () => handoff.decodePackage('{not-json'),
      throwsFormatException,
    );
  });

  test('Build 182 conflict resolution can prefer imported entry', () {
    final localRow = _row(
      id: 'entry-11',
      hour: 13,
      time: '1:00 PM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 13).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'local-note',
    );
    final importedRow = _row(
      id: 'entry-11',
      hour: 13,
      time: '1:00 PM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 13).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'imported-note',
    );

    final local = _shiftWithRows([localRow]);
    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.1',
      buildNumber: '182',
      handoffId: 'handoff-8',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach Energy',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [importedRow.toJson()],
    );

    final merged = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
        company: 'Mach',
        padName: 'Horse Pad',
        wells: const ['Horse 16-2H'],
      ),
      package: package,
    );

    final resolved = handoff.applyConflictResolutions(
      mergeResult: merged,
      preferImportedEntryIds: const {'entry-11'},
    );

    expect(resolved.savedRows.single.notes, 'imported-note');
  });

  test('Build 182 conflict resolution keeps local when not selected', () {
    final localRow = _row(
      id: 'entry-12',
      hour: 14,
      time: '2:00 PM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 14).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'local-kept',
    );
    final importedRow = _row(
      id: 'entry-12',
      hour: 14,
      time: '2:00 PM',
      well: 'Horse 16-2H',
      timestampIso: DateTime(2026, 7, 27, 14).toIso8601String(),
      productionDay: '2026-07-27',
      notes: 'imported-ignored',
    );

    final local = _shiftWithRows([localRow]);
    final package = ShiftHandoffPackage(
      fileType: ShiftHandoffService.currentFileType,
      schemaVersion: ShiftHandoffService.currentSchemaVersion,
      appVersion: '1.0.1',
      buildNumber: '182',
      handoffId: 'handoff-9',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-1',
      jobType: 'production',
      customer: 'Mach Energy',
      jobName: 'Horse Pad',
      productionShift: local.toJson(),
      productionRows: [importedRow.toJson()],
    );

    final merged = handoff.mergePackage(
      localShift: local,
      activeJob: JobSetup(
        company: 'Mach',
        padName: 'Horse Pad',
        wells: const ['Horse 16-2H'],
      ),
      package: package,
    );

    final resolved = handoff.applyConflictResolutions(
      mergeResult: merged,
      preferImportedEntryIds: const <String>{},
    );

    expect(resolved.savedRows.single.notes, 'local-kept');
  });
}
