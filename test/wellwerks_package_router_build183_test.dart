import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/services/wellwerks_package_router_service.dart';

void main() {
  const router = WellWerksPackageRouterService();

  test('Build 183 router detects job setup package type', () {
    const raw = '{"fileType":"wellwerks_job_setup","schemaVersion":"1.0.0"}';
    final header = router.decodeHeader(raw);
    expect(header.type, WellWerksPackageType.jobSetup);
  });

  test('Build 183 router detects production handoff package type', () {
    const raw =
        '{"fileType":"wellwerks_production_handoff","schemaVersion":"1.0.0"}';
    final header = router.decodeHeader(raw);
    expect(header.type, WellWerksPackageType.productionHandoff);
  });

  test('Build 183 router maps legacy active job type to job setup', () {
    const raw = '{"fileType":"wellwerks_active_job","schemaVersion":"1.0.0"}';
    final header = router.decodeHeader(raw);
    expect(header.type, WellWerksPackageType.jobSetup);
  });

  test('Build 183 router accepts legacy active job with no schema', () {
    const raw = '{"fileType":"wellwerks_active_job"}';
    final header = router.decodeHeader(raw);
    expect(header.type, WellWerksPackageType.jobSetup);
    expect(header.schemaVersion, '1.0.0');
  });

  test('Build 183 router detects drillout handoff package type', () {
    const raw =
        '{"fileType":"wellwerks_drillout_handoff","schemaVersion":"1.0.0"}';
    final header = router.decodeHeader(raw);
    expect(header.type, WellWerksPackageType.drilloutHandoff);
  });

  test('Build 183 router rejects unsupported type', () {
    const raw = '{"fileType":"unsupported_type","schemaVersion":"1.0.0"}';
    expect(() => router.decodeHeader(raw), throwsFormatException);
  });

  test('Build 183 router rejects empty payload values', () {
    const raw = '{"fileType":"","schemaVersion":""}';
    expect(() => router.decodeHeader(raw), throwsFormatException);
  });
}
