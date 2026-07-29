import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/operations_log_entry.dart';
import 'package:wellwerks/services/operator_profile_service.dart';
import 'package:wellwerks/services/operations_log_service.dart';

void main() {
  final service = OperationsLogService();

  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel =
      MethodChannel('dev.fluttercommunity.plus/package_info');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OperatorProfileService.instance.updateProfile(
      name: 'Jane Doe',
      initials: 'JD',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'WellWerks',
          'packageName': 'wellwerks',
          'version': '1.0.1',
          'buildNumber': '188',
          'buildSignature': 'signature',
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
  });

  test('operations log qr package roundtrip preserves entry ids and timestamps',
      () async {
    final entry = OperationsLogEntry(
      entryId: 'entry-1',
      packageCompatibleEntryId: 'pkg-entry-1',
      workflow: 'drillout',
      persistentJobId: 'job-1',
      persistentWellId: 'well-1',
      wellName: 'Well 1',
      readingTimestamp: DateTime(2026, 7, 28, 7, 18),
      createdAt: DateTime(2026, 7, 28, 7, 18),
      lastModifiedAt: DateTime(2026, 7, 28, 7, 18),
      sourceBuildNumber: '188',
      sourceOperatorId: 'op-1',
      sourceOperatorName: 'Jane Doe',
      sourceOperatorInitials: 'JD',
      sourceDeviceId: 'dev-1',
      isImported: false,
      qrPackageId: 'pkg-123',
      operationStage: 'Stage 1',
      pumpRate: '12.5',
    );

    final package = await service.buildPackage(
      packageType: OperationsLogPackageType.drilloutReading,
      persistentJobId: 'job-1',
      entries: [entry],
    );
    final encoded = service.encodePackage(package);
    final decoded = service.decodePackage(encoded);

    expect(decoded.packageType, 'drilloutReading');
    expect(decoded.entries.single.entryId, 'entry-1');
    expect(decoded.entries.single.readingTimestamp, entry.readingTimestamp);
    expect(decoded.sourceOperatorInitials, 'JD');
  });

  test('operations log import rejects workflow mismatch', () async {
    final entry = OperationsLogEntry(
      entryId: 'entry-1',
      packageCompatibleEntryId: 'pkg-entry-1',
      workflow: 'cleanout',
      persistentJobId: 'job-1',
      persistentWellId: 'well-1',
      wellName: 'Well 1',
      readingTimestamp: DateTime(2026, 7, 28, 7, 18),
      createdAt: DateTime(2026, 7, 28, 7, 18),
      lastModifiedAt: DateTime(2026, 7, 28, 7, 18),
      sourceBuildNumber: '188',
      sourceOperatorId: 'op-1',
      sourceOperatorName: 'Jane Doe',
      sourceOperatorInitials: 'JD',
      sourceDeviceId: 'dev-1',
      isImported: false,
    );
    final package = OperationsLogPackage(
      fileType: 'wellwerks_operations_log',
      schemaVersion: '1.0.0',
      packageType: 'cleanoutReading',
      packageId: 'pkg-1',
      createdAt: DateTime(2026, 7, 28, 7, 18).toIso8601String(),
      sourceBuildNumber: '188',
      sourceOperatorId: 'op-1',
      sourceOperatorName: 'Jane Doe',
      sourceOperatorInitials: 'JD',
      sourceDeviceId: 'dev-1',
      persistentJobId: 'job-1',
      workflow: 'cleanout',
      entries: [entry],
    );

    expect(
      () => service.importEntries(
        workflow: OperationsLogWorkflow.drillout,
        jobId: 'job-1',
        package: package,
        existingEntries: const [],
      ),
      throwsFormatException,
    );
  });

  test('operations log compact shift report builds a pdf payload', () async {
    final entry = OperationsLogEntry(
      entryId: 'entry-1',
      packageCompatibleEntryId: 'pkg-entry-1',
      workflow: 'drillout',
      persistentJobId: 'job-1',
      persistentWellId: 'well-1',
      wellName: 'Well 1',
      readingTimestamp: DateTime(2026, 7, 28, 7, 18),
      createdAt: DateTime(2026, 7, 28, 7, 18),
      lastModifiedAt: DateTime(2026, 7, 28, 7, 18),
      sourceBuildNumber: '188',
      sourceOperatorId: 'op-1',
      sourceOperatorName: 'Jane Doe',
      sourceOperatorInitials: 'JD',
      sourceDeviceId: 'dev-1',
      isImported: false,
      operationStage: 'Stage 1',
      pumpRate: '12.5',
      casingPressure: '510',
      tubingPressure: '245',
      notes: 'Stable conditions',
    );

    final bytes = await service.buildShiftReportPdfBytes(
      workflow: OperationsLogWorkflow.drillout,
      jobName: 'Pad 7',
      wellName: 'Well 1',
      stage: 'Stage 1',
      entries: [entry],
    );

    expect(bytes.length, greaterThan(1000));
    expect(bytes.take(4).toList(), equals(<int>[0x25, 0x50, 0x44, 0x46]));
  });
}
