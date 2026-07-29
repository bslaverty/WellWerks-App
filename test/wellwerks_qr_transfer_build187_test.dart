import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/services/active_job_share_service.dart';
import 'package:wellwerks/services/job_setup_import_service.dart';
import 'package:wellwerks/services/wellwerks_qr_transfer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const transfer = WellWerksQrTransferService();
  const share = ActiveJobShareService();
  const importer = JobSetupImportService();
  final tinyPngBytes = Uint8List.fromList(<int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    13,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    248,
    255,
    255,
    255,
    127,
    0,
    9,
    251,
    3,
    253,
    5,
    67,
    69,
    202,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ]);

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

  testWidgets('Build 191 QR PNG bytes decode correctly', (tester) async {
    final bytes = await transfer
        .buildQrPngBytes('WWJOBQR1:TEST_PAYLOAD')
        .timeout(const Duration(seconds: 20));

    expect(bytes, isNotEmpty);
    expect(
        bytes.take(8).toList(), equals(<int>[137, 80, 78, 71, 13, 10, 26, 10]));

    final decoded = img.decodePng(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, greaterThan(0));
    expect(decoded.height, greaterThan(0));
  });

  test('Build 191 shared QR image service saves PNG and opens share sheet',
      () async {
    List<XFile>? sharedFiles;
    String? sharedSubject;
    String? sharedText;
    Rect? sharedOrigin;

    final service = WellWerksQrTransferService(
      fileSaver: (bytes, fileName) async {
        final file = File('build/test_tmp/$fileName');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        return file;
      },
      qrPngBytesBuilder: (qrValue, {size = 1200}) async => tinyPngBytes,
      shareExecutor: (files,
          {String? subject, String? text, Rect? sharePositionOrigin}) async {
        sharedFiles = files;
        sharedSubject = subject;
        sharedText = text;
        sharedOrigin = sharePositionOrigin;
        return const ShareResult('ok', ShareResultStatus.success);
      },
    );

    final result = await service.shareQrPng(
      qrValue: 'WWJOBQR1:TEST_PAYLOAD',
      fileName: 'Share Reading QR',
      shareContext: null,
      subject: 'Share Reading QR',
      text: 'Share Reading QR',
    );

    expect(result.status, ShareResultStatus.success);
    expect(sharedFiles, isNotNull);
    expect(sharedFiles, hasLength(1));
    expect(sharedFiles!.single.mimeType, 'image/png');
    expect(sharedSubject, 'Share Reading QR');
    expect(sharedText, 'Share Reading QR');
    expect(sharedOrigin, isNull);
    expect(await File(sharedFiles!.single.path).exists(), isTrue);
  });

  test('Build 191 QR share dismissal is treated as cancel', () async {
    final service = WellWerksQrTransferService(
      fileSaver: (bytes, fileName) async {
        final file = File('build/test_tmp/$fileName');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        return file;
      },
      qrPngBytesBuilder: (qrValue, {size = 1200}) async => tinyPngBytes,
      shareExecutor: (files,
          {String? subject, String? text, Rect? sharePositionOrigin}) async {
        return const ShareResult('dismissed', ShareResultStatus.dismissed);
      },
    );

    final result = await service.shareQrPng(
      qrValue: 'WWJOBQR1:TEST_PAYLOAD',
      fileName: 'Share Reading QR',
      shareContext: null,
    );

    expect(result.status, ShareResultStatus.dismissed);
  });
}
