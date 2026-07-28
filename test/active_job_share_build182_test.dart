import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/services/active_job_share_service.dart';

void main() {
  test('Build 182 active job share roundtrip keeps drillout workflow data', () {
    final package = ActiveJobSharePackage(
      fileType: ActiveJobShareService.currentFileType,
      schemaVersion: ActiveJobShareService.currentSchemaVersion,
      appVersion: '1.0.1',
      buildNumber: '182',
      exportedAt: DateTime(2026, 7, 27, 18).toIso8601String(),
      sourceJobId: 'job-drillout-1',
      workflow: 'drillout',
      jobData: JobSetup(
        id: 'job-drillout-1',
        company: 'Mach Energy',
        workflow: 'drillout',
        shift: 'Night',
        padName: 'Pad 11',
        wells: const ['Well A'],
        wellEntries: const [JobSetupWell(id: 'well-a', name: 'Well A')],
        drilloutSetup: const {
          'manifoldPsi': '300',
          'casingPsi': '120',
          'flowbackGauge': '40',
        },
      ).toJson(),
    );

    const service = ActiveJobShareService();
    final encoded = service.encodePackage(package);
    final decoded = service.decodePackage(encoded);

    expect(decoded.sourceJobId, 'job-drillout-1');
    expect(decoded.workflow, 'drillout');

    final imported = JobSetup.fromJson(decoded.jobData);
    expect(imported.workflow, 'drillout');
    expect(imported.drilloutSetup['manifoldPsi'], '300');
    expect(imported.resolvedWellNames, ['Well A']);
  });

  test('Build 182 active job share rejects unsupported schema', () {
    const service = ActiveJobShareService();
    const raw = '{"fileType":"wellwerks_job_setup","schemaVersion":"9.9.9"}';
    expect(() => service.decodePackage(raw), throwsFormatException);
  });

  test('Build 182 active job share rejects unsupported type', () {
    const service = ActiveJobShareService();
    const raw = '{"fileType":"wrong_type","schemaVersion":"1.0.0"}';
    expect(() => service.decodePackage(raw), throwsFormatException);
  });

  test('Build 183 import accepts legacy active job file type', () {
    const service = ActiveJobShareService();
    const raw =
        '{"fileType":"wellwerks_active_job","schemaVersion":"1.0.0","workflow":"production","jobData":{"company":"Mach Energy"}}';

    final decoded = service.decodePackage(raw);
    expect(decoded.fileType, 'wellwerks_active_job');
    expect(decoded.workflow, 'production');
  });

  test('Build 183 import accepts legacy active job with no schema', () {
    const service = ActiveJobShareService();
    const raw =
        '{"fileType":"wellwerks_active_job","workflow":"production","jobData":{"company":"Mach Energy"}}';

    final decoded = service.decodePackage(raw);
    expect(decoded.fileType, 'wellwerks_active_job');
    expect(decoded.workflow, 'production');
  });
}
