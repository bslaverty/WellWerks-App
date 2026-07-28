import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/services/drillout_handoff_service.dart';

void main() {
  final service = DrilloutHandoffService();

  test('Build 183 drillout handoff roundtrip preserves setup text fields', () {
    final package = DrilloutHandoffPackage(
      fileType: DrilloutHandoffService.currentFileType,
      schemaVersion: DrilloutHandoffService.currentSchemaVersion,
      appVersion: '1.0.1',
      buildNumber: '183',
      handoffId: 'drillout_handoff_1',
      exportedAt: DateTime(2026, 7, 28, 6).toIso8601String(),
      sourceJobId: 'job-drillout-22',
      workflow: 'drillout',
      customer: 'Mach Energy',
      jobName: 'Pad 22',
      jobData: JobSetup(
        id: 'job-drillout-22',
        company: 'Mach Energy',
        workflow: 'drillout',
        padName: 'Pad 22',
        wells: const ['Well 22A'],
        wellEntries: const [JobSetupWell(id: 'well-22a', name: 'Well 22A')],
        drilloutSetup: const {
          'wellName': 'Well 22A',
          'status': 'Circulating',
          'manifoldPsi': '320',
          'notes': 'All systems stable',
        },
      ).toJson(),
    );

    final encoded = service.encodePackage(package);
    final decoded = service.decodePackage(encoded);
    final importedJob = service.importAsActiveJob(decoded);

    expect(decoded.sourceJobId, 'job-drillout-22');
    expect(importedJob.workflow, 'drillout');
    expect(importedJob.drilloutSetup['manifoldPsi'], '320');
    expect(importedJob.drilloutSetup['notes'], 'All systems stable');
    expect(importedJob.resolvedWellNames, const ['Well 22A']);
  });

  test('Build 183 drillout handoff normalizes cleanout workflow', () {
    final package = DrilloutHandoffPackage(
      fileType: DrilloutHandoffService.currentFileType,
      schemaVersion: DrilloutHandoffService.currentSchemaVersion,
      appVersion: '1.0.1',
      buildNumber: '183',
      handoffId: 'drillout_handoff_2',
      exportedAt: DateTime(2026, 7, 28, 6).toIso8601String(),
      sourceJobId: 'job-cleanout-1',
      workflow: 'cleanout',
      customer: 'Mach Energy',
      jobName: 'Pad C1',
      jobData: JobSetup(
        id: 'job-cleanout-1',
        company: 'Mach Energy',
        workflow: 'cleanout',
        padName: 'Pad C1',
      ).toJson(),
    );

    final importedJob = service.importAsActiveJob(package);
    expect(importedJob.workflow, 'cleanout');
    expect(importedJob.status, 'active');
  });

  test('Build 183 drillout handoff rejects wrong file type', () {
    const raw =
        '{"fileType":"wellwerks_production_handoff","schemaVersion":"1.0.0"}';
    expect(() => service.decodePackage(raw), throwsFormatException);
  });
}
