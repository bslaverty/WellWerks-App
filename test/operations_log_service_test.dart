import 'dart:convert';

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
    final estimatedSts = DateTime(2026, 7, 29, 23, 35);
    final sts = DateTime(2026, 7, 30, 0, 5);
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
      gas: 'Medium',
      sandOrSolids: 'Light',
      choke: '24/64" Positive',
      pumpRate: '12.5',
      returnsRate: '10.0',
      estimatedSts: estimatedSts,
      sts: sts,
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
    expect(decoded.entries.single.gas, 'Medium');
    expect(decoded.entries.single.sandOrSolids, 'Light');
    expect(decoded.entries.single.choke, '24/64" Positive');
    expect(decoded.entries.single.returnsRate, '10.0');
    expect(decoded.entries.single.estimatedSts, estimatedSts);
    expect(decoded.entries.single.sts, sts);
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
    final sts = DateTime(2026, 7, 29, 0, 5);
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
      returnsRate: '11.0',
      casingPressure: '510',
      tubingPressure: '245',
      estimatedSts: DateTime(2026, 7, 28, 23, 35),
      sts: sts,
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
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, contains('(Estimated)'));
    expect(text, contains('(STS)'));
    expect(text, contains('(12:05)'));
  });

  test('operations log entries persist estimated STS and STS timestamps',
      () async {
    const workflow = OperationsLogWorkflow.drillout;
    const jobId = 'job-191';
    final created = await service.createLocalEntry(
      workflow: workflow,
      jobId: jobId,
      wellId: 'well-1',
      wellName: 'Well 1',
      readingTimestamp: DateTime(2026, 7, 29, 23, 30),
      pumpRate: '12.0',
      returnsRate: '9.5',
      estimatedSts: DateTime(2026, 7, 29, 23, 35),
      sts: DateTime(2026, 7, 30, 0, 5),
    );

    await service.upsertEntry(
      workflow: workflow,
      jobId: jobId,
      entry: created,
    );

    final loaded = await service.loadEntries(workflow: workflow, jobId: jobId);
    expect(loaded, hasLength(1));
    expect(loaded.single.estimatedSts, DateTime(2026, 7, 29, 23, 35));
    expect(loaded.single.sts, DateTime(2026, 7, 30, 0, 5));
  });
}
