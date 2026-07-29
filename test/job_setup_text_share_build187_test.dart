import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/services/active_job_share_service.dart';
import 'package:wellwerks/services/job_setup_import_service.dart';

void main() {
  const importService = JobSetupImportService();
  const shareService = ActiveJobShareService();

  ActiveJobSharePackage packageFor(JobSetup job) {
    return ActiveJobSharePackage(
      fileType: ActiveJobShareService.currentFileType,
      schemaVersion: ActiveJobShareService.currentSchemaVersion,
      packageId: 'pkg-187',
      appVersion: '1.0.1',
      buildNumber: '187',
      packageCreatedAt: DateTime(2026, 7, 28, 12).toIso8601String(),
      sourceJobId: job.id,
      customer: job.company,
      jobName: job.padName,
      workflow: job.workflow,
      wells: job.resolvedWellNames,
      wellIds: job.wellIds,
      jobData: job.toJson(),
    );
  }

  test('Build 187 text share message includes prefix and nonempty payload', () {
    final job = JobSetup(
      id: 'job-187-a',
      company: 'Mach Energy',
      padName: 'Gathers Pad',
      workflow: 'production',
      wellEntries: const [JobSetupWell(id: 'well-1', name: 'Well 1')],
      oilTanks: 4,
      waterTanks: 6,
      productionTankFactor: '1.67',
    );
    final package = packageFor(job);

    final message = importService.buildTextShareMessage(
      package: package,
      company: job.company,
      padOrJob: job.padName,
    );

    expect(message, contains(JobSetupImportService.importCodePrefix));
    final raw = importService.extractImportCodePayload(message);
    expect(raw.trim().isNotEmpty, isTrue);
  });

  test(
      'Build 187 text share reuses structured payload and decodes as job setup',
      () {
    final job = JobSetup(
      id: 'job-187-b',
      company: 'Mach Energy',
      padName: 'Horse Pad',
      workflow: 'drillout',
      wellEntries: const [JobSetupWell(id: 'well-a', name: 'Well A')],
      oilTanks: 3,
      waterTanks: 2,
      productionTankFactor: '1.25',
    );

    final package = packageFor(job);
    final expectedRaw = shareService.encodePackage(package);
    final message = importService.buildTextShareMessage(
      package: package,
      company: job.company,
      padOrJob: job.padName,
    );

    final extractedRaw = importService.extractImportCodePayload(message);
    expect(jsonDecode(extractedRaw), jsonDecode(expectedRaw));

    final preview =
        importService.decodePreview(raw: extractedRaw, localJobs: const []);
    expect(preview.package.fileType, ActiveJobShareService.currentFileType);
    expect(preview.job.company, 'Mach Energy');
    expect(preview.job.padName, 'Horse Pad');
    expect(preview.job.workflow, 'drillout');
    expect(preview.job.resolvedWellNames, ['Well A']);
    expect(preview.job.oilTanks, 3);
    expect(preview.job.waterTanks, 2);
    expect(preview.job.productionTankFactor, '1.25');
  });

  test('Build 187 zero operational entries do not block text package', () {
    final job = JobSetup(
      id: 'job-187-c',
      company: 'Mach Energy',
      padName: 'Zero Ops',
      workflow: 'production',
      wellEntries: const [JobSetupWell(id: 'well-z', name: 'Well Z')],
    );

    final message = importService.buildTextShareMessage(
      package: packageFor(job),
      company: job.company,
      padOrJob: job.padName,
    );
    final preview = importService.decodePreview(
      raw: importService.extractImportCodePayload(message),
      localJobs: const [],
    );
    expect(preview.job.padName, 'Zero Ops');
  });

  test('Build 187 importer accepts intro text and harmless whitespace', () {
    final job = JobSetup(
      id: 'job-187-d',
      company: 'Mach Energy',
      padName: 'Whitespace Pad',
      workflow: 'production',
    );

    final code = importService.buildImportCode(packageFor(job));
    final wrapped = '  Message before code\n\n  $code  \n\n';
    final raw = importService.extractImportCodePayload(wrapped);
    final preview = importService.decodePreview(raw: raw, localJobs: const []);
    expect(preview.job.padName, 'Whitespace Pad');
  });

  test('Build 187 incomplete text is rejected', () {
    const broken = '${JobSetupImportService.importCodePrefix}abcd';
    expect(
      () => importService.extractImportCodePayload(broken),
      throwsFormatException,
    );
  });

  test('Build 187 invalid prefix is rejected', () {
    expect(
      () => importService.extractImportCodePayload('NOT_WELLWERKS:abc123'),
      throwsFormatException,
    );
  });

  test('Build 187 invalid encoded data is rejected', () {
    const invalid = '${JobSetupImportService.importCodePrefix}%%%%';
    expect(
      () => importService.extractImportCodePayload(invalid),
      throwsFormatException,
    );
  });

  test('Build 187 wrong fileType is rejected', () {
    final wrongTypeRaw = jsonEncode({
      'fileType': 'wellwerks_production_handoff',
      'schemaVersion': ActiveJobShareService.currentSchemaVersion,
      'sourceJobId': 'job-wrong-type',
      'workflow': 'production',
      'jobData': {'company': 'Mach Energy'},
    });
    final encoded = base64UrlEncode(utf8.encode(wrongTypeRaw));
    final text = '${JobSetupImportService.importCodePrefix}$encoded';

    final payload = importService.extractImportCodePayload(text);
    expect(
      () => importService.decodePreview(raw: payload, localJobs: const []),
      throwsFormatException,
    );
  });

  test('Build 187 newer schema is rejected', () {
    final raw = jsonEncode({
      'fileType': ActiveJobShareService.currentFileType,
      'schemaVersion': '9.9.9',
      'sourceJobId': 'job-new-schema',
      'workflow': 'production',
      'jobData': {'company': 'Mach Energy'},
    });
    final encoded = base64UrlEncode(utf8.encode(raw));
    final text = '${JobSetupImportService.importCodePrefix}$encoded';

    final payload = importService.extractImportCodePayload(text);
    expect(
      () => importService.decodePreview(raw: payload, localJobs: const []),
      throwsFormatException,
    );
  });
}
