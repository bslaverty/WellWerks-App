import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/services/active_job_share_service.dart';
import 'package:wellwerks/services/job_setup_import_service.dart';
import 'package:wellwerks/services/wellwerks_qr_transfer_service.dart';

void main() {
  const transfer = WellWerksQrTransferService();
  const share = ActiveJobShareService();
  const importer = JobSetupImportService();

  ActiveJobSharePackage packageFor(JobSetup job) {
    return ActiveJobSharePackage(
      fileType: ActiveJobShareService.currentFileType,
      schemaVersion: ActiveJobShareService.currentSchemaVersion,
      packageId: 'pkg-187-qr',
      appVersion: '1.0.1',
      buildNumber: '187',
      packageCreatedAt: DateTime(2026, 7, 28, 14).toIso8601String(),
      sourceJobId: job.id,
      customer: job.company,
      jobName: job.padName,
      workflow: job.workflow,
      wells: job.resolvedWellNames,
      wellIds: job.wellIds,
      jobData: job.toJson(),
    );
  }

  test('Build 187 Job Setup QR transfer roundtrip preserves payload', () {
    final job = JobSetup(
      id: 'job-187-qr-1',
      company: 'Mach Energy',
      padName: 'Gathers Pad',
      workflow: 'production',
      wellEntries: const [JobSetupWell(id: 'well-1', name: 'Well 1')],
      oilTanks: 4,
      waterTanks: 6,
    );

    final raw = share.encodePackage(packageFor(job));
    final qr = transfer.encodeStructuredPayload(raw);
    transfer.ensureSingleQrCapacity(qr);
    final decoded = transfer.decodeStructuredPayload(qr);

    expect(jsonDecode(decoded), jsonDecode(raw));

    final preview = importer.decodePreview(raw: decoded, localJobs: const []);
    expect(preview.job.company, 'Mach Energy');
    expect(preview.job.padName, 'Gathers Pad');
    expect(preview.job.resolvedWellNames, ['Well 1']);
  });

  test('Build 187 QR transfer handles zero operational entries', () {
    final job = JobSetup(
      id: 'job-187-qr-2',
      company: 'Mach Energy',
      padName: 'Zero Ops',
      workflow: 'production',
      wellEntries: const [JobSetupWell(id: 'well-z', name: 'Well Z')],
    );

    final raw = share.encodePackage(packageFor(job));
    final qr = transfer.encodeStructuredPayload(raw);
    final decoded = transfer.decodeStructuredPayload(qr);
    final preview = importer.decodePreview(raw: decoded, localJobs: const []);

    expect(preview.job.padName, 'Zero Ops');
  });

  test('Build 187 QR transfer rejects oversized single-code payload', () {
    final oversizedQrValue = List.filled(20000, 'A').join();
    expect(
      () => transfer.ensureSingleQrCapacity(oversizedQrValue),
      throwsFormatException,
    );
  });

  test('Build 187 filename sanitization removes invalid characters', () {
    final name = transfer.sanitizeFilePart('Pad 12/West:?*');
    expect(name, 'Pad_12_West_');
  });
}
