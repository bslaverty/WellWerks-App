import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/services/job_setup_qr_service.dart';

void main() {
  const service = JobSetupQrService();

  test('Build 183 Job Setup QR roundtrip preserves package JSON', () {
    const raw =
        '{"fileType":"wellwerks_job_setup","schemaVersion":"1.0.0","jobData":{"company":"Mach"}}';

    final payload = service.encodePayload(raw);
    final decoded = service.decodePayload(payload);

    expect(payload.startsWith(JobSetupQrService.currentPrefix), isTrue);
    expect(decoded, raw);
  });

  test('Build 183 Job Setup QR decode supports legacy direct JSON', () {
    const raw = '{"fileType":"wellwerks_job_setup","schemaVersion":"1.0.0"}';
    expect(service.decodePayload(raw), raw);
  });

  test('Build 183 Job Setup QR rejects unsupported payload', () {
    expect(
      () => service.decodePayload('not-a-valid-qr-payload'),
      throwsFormatException,
    );
  });

  test('Build 183 Job Setup QR can split and reassemble chunk frames', () {
    final longData =
        List<String>.generate(800, (index) => 'well_$index').join(',');
    final raw =
        '{"fileType":"wellwerks_job_setup","schemaVersion":"1.0.0","jobData":{"wells":"$longData"}}';

    final frames = service.encodePayloadFrames(raw, maxFrameLength: 240);
    expect(frames.length, greaterThan(1));
    for (final frame in frames) {
      expect(frame.length <= 240, isTrue);
    }

    final assembled = service.assembleChunkFrames(frames);
    final decoded = service.decodePayload(assembled);
    expect(decoded, raw);
  });

  test('Build 183 Job Setup QR parser recognizes chunk frames', () {
    const chunk =
        'WWJOBQR1C:abc123:2/4:ZXlKc2IyTnNZWFpoYkM1amIyMHVjR0YwYUNJNkltbGs=';
    final parsed = service.tryParseChunkFrame(chunk);

    expect(parsed, isNotNull);
    expect(parsed!.sessionId, 'abc123');
    expect(parsed.index, 2);
    expect(parsed.total, 4);
    expect(parsed.data, 'ZXlKc2IyTnNZWFpoYkM1amIyMHVjR0YwYUNJNkltbGs=');
  });

  test('Build 183 Job Setup QR chunk assembly rejects missing pieces', () {
    const frames = <String>[
      'WWJOBQR1C:sessionx:1/3:AAAA',
      'WWJOBQR1C:sessionx:3/3:CCCC',
    ];
    expect(() => service.assembleChunkFrames(frames), throwsFormatException);
  });

  test('Build 183 Job Setup QR parser rejects invalid chunk numbering', () {
    const badChunk = 'WWJOBQR1C:abc123:5/4:DATA';
    expect(() => service.tryParseChunkFrame(badChunk), throwsFormatException);
  });
}
