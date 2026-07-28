import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class JobSetupQrChunkFrame {
  const JobSetupQrChunkFrame({
    required this.sessionId,
    required this.index,
    required this.total,
    required this.data,
  });

  final String sessionId;
  final int index;
  final int total;
  final String data;
}

class JobSetupQrService {
  const JobSetupQrService();

  static const String currentPrefix = 'WWJOBQR1:';
  static const String chunkPrefix = 'WWJOBQR1C:';
  static const int maxRecommendedPayloadLength = 2400;
  static const int defaultMaxFrameLength = 2200;

  String encodePayload(String packageRawJson) {
    final raw = packageRawJson.trim();
    if (raw.isEmpty) {
      throw const FormatException('Cannot encode empty Job Setup payload.');
    }
    final compressed = _gzip(Uint8List.fromList(utf8.encode(raw)));
    final base64 = base64UrlEncode(compressed);
    return '$currentPrefix$base64';
  }

  String decodePayload(String qrRawValue) {
    final value = qrRawValue.trim();
    if (value.isEmpty) {
      throw const FormatException('QR payload is empty.');
    }

    // Backward-compatible path: direct JSON payload.
    if (value.startsWith('{') && value.endsWith('}')) {
      return value;
    }

    if (!value.startsWith(currentPrefix)) {
      throw const FormatException('Unsupported Job Setup QR payload format.');
    }

    final encoded = value.substring(currentPrefix.length);
    if (encoded.isEmpty) {
      throw const FormatException('Job Setup QR payload is missing data.');
    }

    try {
      final compressed = base64Url.decode(encoded);
      final decompressed = _gunzip(Uint8List.fromList(compressed));
      final raw = utf8.decode(decompressed);
      if (raw.trim().isEmpty) {
        throw const FormatException('Decoded Job Setup QR payload is empty.');
      }
      return raw;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Failed to decode Job Setup QR payload.');
    }
  }

  List<String> encodePayloadFrames(
    String packageRawJson, {
    int maxFrameLength = defaultMaxFrameLength,
  }) {
    final single = encodePayload(packageRawJson);
    if (single.length <= maxFrameLength) {
      return <String>[single];
    }

    final encoded = single.substring(currentPrefix.length);
    if (encoded.isEmpty) {
      throw const FormatException('Cannot chunk an empty Job Setup payload.');
    }

    if (maxFrameLength < 200) {
      throw const FormatException('QR frame limit is too small for chunking.');
    }

    final sessionId = _buildSessionId(encoded);
    var chunkSize = maxFrameLength - 80;
    if (chunkSize <= 0) {
      throw const FormatException('QR frame limit is too small for chunking.');
    }

    while (chunkSize > 0) {
      final total = (encoded.length / chunkSize).ceil();
      final frames = <String>[];
      var valid = true;
      for (var i = 0; i < total; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize) > encoded.length
            ? encoded.length
            : (start + chunkSize);
        final part = encoded.substring(start, end);
        final frame = '$chunkPrefix$sessionId:${i + 1}/$total:$part';
        if (frame.length > maxFrameLength) {
          valid = false;
          break;
        }
        frames.add(frame);
      }
      if (valid) {
        return frames;
      }
      chunkSize -= 20;
    }

    throw const FormatException('Unable to chunk Job Setup payload for QR.');
  }

  JobSetupQrChunkFrame? tryParseChunkFrame(String qrRawValue) {
    final value = qrRawValue.trim();
    if (!value.startsWith(chunkPrefix)) return null;

    final body = value.substring(chunkPrefix.length);
    final colonIndex = body.indexOf(':');
    if (colonIndex <= 0) {
      throw const FormatException('Invalid Job Setup QR chunk header.');
    }
    final sessionId = body.substring(0, colonIndex).trim();
    if (sessionId.isEmpty) {
      throw const FormatException('Job Setup QR chunk missing session id.');
    }

    final remainder = body.substring(colonIndex + 1);
    final secondColonIndex = remainder.indexOf(':');
    if (secondColonIndex <= 0) {
      throw const FormatException('Invalid Job Setup QR chunk sequence.');
    }

    final seq = remainder.substring(0, secondColonIndex).trim();
    final slashIndex = seq.indexOf('/');
    if (slashIndex <= 0) {
      throw const FormatException('Invalid Job Setup QR chunk numbering.');
    }

    final indexRaw = seq.substring(0, slashIndex).trim();
    final totalRaw = seq.substring(slashIndex + 1).trim();
    final index = int.tryParse(indexRaw) ?? -1;
    final total = int.tryParse(totalRaw) ?? -1;
    if (index <= 0 || total <= 0 || index > total) {
      throw const FormatException('Invalid Job Setup QR chunk index/total.');
    }

    final data = remainder.substring(secondColonIndex + 1);
    if (data.isEmpty) {
      throw const FormatException('Job Setup QR chunk has no payload data.');
    }

    return JobSetupQrChunkFrame(
      sessionId: sessionId,
      index: index,
      total: total,
      data: data,
    );
  }

  String assembleChunkFrames(Iterable<String> rawFrames) {
    final frames = <JobSetupQrChunkFrame>[];
    for (final raw in rawFrames) {
      final parsed = tryParseChunkFrame(raw);
      if (parsed == null) {
        throw const FormatException('Mixed QR formats in chunk assembly.');
      }
      frames.add(parsed);
    }

    if (frames.isEmpty) {
      throw const FormatException(
          'No Job Setup QR chunk frames were provided.');
    }

    final sessionId = frames.first.sessionId;
    final total = frames.first.total;
    final byIndex = <int, String>{};

    for (final frame in frames) {
      if (frame.sessionId != sessionId) {
        throw const FormatException(
            'Job Setup QR chunks are from different sessions.');
      }
      if (frame.total != total) {
        throw const FormatException('Job Setup QR chunk totals do not match.');
      }
      byIndex[frame.index] = frame.data;
    }

    if (byIndex.length != total) {
      throw FormatException(
        'Missing Job Setup QR chunk(s). Have ${byIndex.length} of $total.',
      );
    }

    final buffer = StringBuffer();
    for (var i = 1; i <= total; i++) {
      final part = byIndex[i];
      if (part == null) {
        throw const FormatException(
            'Job Setup QR chunks are missing sequence entries.');
      }
      buffer.write(part);
    }

    return '$currentPrefix${buffer.toString()}';
  }

  String _buildSessionId(String encodedPayload) {
    final hash = encodedPayload.hashCode.abs();
    final mixed = (hash ^ encodedPayload.length).abs();
    return mixed.toRadixString(36);
  }

  Uint8List _gzip(Uint8List input) {
    final encoded = GZipEncoder().encode(input);
    if (encoded == null) {
      throw const FormatException('Failed to compress Job Setup QR payload.');
    }
    return Uint8List.fromList(encoded);
  }

  Uint8List _gunzip(Uint8List input) {
    final decoded = GZipDecoder().decodeBytes(input);
    return Uint8List.fromList(decoded);
  }
}
