import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/services/active_job_share_service.dart';
import 'package:wellwerks/services/job_setup_import_service.dart';

void main() {
  const importService = JobSetupImportService();
  const shareService = ActiveJobShareService();

  ActiveJobSharePackage packageFor(JobSetup job, {String? sourceJobId}) {
    return ActiveJobSharePackage(
      fileType: ActiveJobShareService.currentFileType,
      schemaVersion: ActiveJobShareService.currentSchemaVersion,
      packageId: 'pkg-186',
      appVersion: '1.0.1',
      buildNumber: '186',
      packageCreatedAt: DateTime(2026, 7, 28, 10).toIso8601String(),
      sourceJobId: sourceJobId ?? job.id,
      customer: job.company,
      jobName: job.padName,
      workflow: job.workflow,
      wells: job.resolvedWellNames,
      wellIds: job.wellIds,
      jobData: job.toJson(),
    );
  }

  test('Build 186 import code roundtrip decodes preview', () {
    final job = JobSetup(
      id: 'job-186-1',
      company: 'Mach Energy',
      padName: 'Horse Pad',
      workflow: 'production',
      wellEntries: const [JobSetupWell(id: 'well-a', name: 'Well A')],
    );
    final package = packageFor(job);

    final code = importService.buildImportCode(package);
    final payload = importService.extractImportCodePayload(code);
    final preview =
        importService.decodePreview(raw: payload, localJobs: const []);

    expect(preview.job.company, 'Mach Energy');
    expect(preview.job.padName, 'Horse Pad');
    expect(preview.hasMatchingJob, isFalse);
  });

  test('Build 186 preview finds matching local job by persistent id', () {
    final incoming = JobSetup(
      id: 'job-186-match',
      company: 'Mach Energy',
      padName: 'Pad 12',
      workflow: 'production',
      wellEntries: const [JobSetupWell(id: 'well-a', name: 'Well A')],
    );

    final raw = shareService.encodePackage(packageFor(incoming));
    final local = [
      JobSetup(
        id: 'job-186-match',
        company: 'Existing Co',
        padName: 'Existing Pad',
        workflow: 'production',
      ),
    ];

    final preview = importService.decodePreview(raw: raw, localJobs: local);
    expect(preview.hasMatchingJob, isTrue);
    expect(preview.matchingJob!.id, 'job-186-match');
  });

  test('Build 186 update matching keeps existing identity/timestamps', () {
    final existingStarted = DateTime(2026, 1, 1, 6);
    final localExisting = JobSetup(
      id: 'job-186-update',
      company: 'Old Company',
      padName: 'Old Pad',
      workflow: 'production',
      startedAt: existingStarted,
      status: 'active',
    );

    final incoming = JobSetup(
      id: 'job-186-update',
      company: 'New Company',
      padName: 'New Pad',
      workflow: 'production',
      oilTanks: 6,
      waterTanks: 3,
    );

    final preview = importService.decodePreview(
      raw: shareService.encodePackage(packageFor(incoming)),
      localJobs: [localExisting],
    );

    final updated = importService.buildImportAsUpdate(preview);
    expect(updated.id, 'job-186-update');
    expect(updated.company, 'New Company');
    expect(updated.padName, 'New Pad');
    expect(updated.startedAt, existingStarted);
    expect(updated.endedAt, isNull);
  });

  test('Build 186 import as new generates unique id when source exists', () {
    final incoming = JobSetup(
      id: 'job-186-existing-id',
      company: 'Mach Energy',
      padName: 'Pad 16',
      workflow: 'production',
    );

    final preview = importService.decodePreview(
      raw: shareService.encodePackage(packageFor(incoming)),
      localJobs: [incoming],
    );

    final imported = importService.buildImportAsNew(
      preview,
      localJobs: [incoming],
    );

    expect(imported.id, isNot('job-186-existing-id'));
    expect(imported.status, 'active');
    expect(imported.endedAt, isNull);
  });
}
