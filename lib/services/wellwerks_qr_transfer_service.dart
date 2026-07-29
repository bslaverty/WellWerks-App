import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'job_setup_qr_service.dart';

class WellWerksQrTransferService {
  // QR version 40 with low error correction in byte mode fits 2953 bytes.
  static const int _singleQrByteModeLimit = 2953;

  const WellWerksQrTransferService({
    JobSetupQrService? payloadCodec,
  }) : _payloadCodec = payloadCodec ?? const JobSetupQrService();

  final JobSetupQrService _payloadCodec;

  String encodeStructuredPayload(String rawJson) {
    return _payloadCodec.encodePayload(rawJson);
  }

  String decodeStructuredPayload(String qrValue) {
    return _payloadCodec.decodePayload(qrValue);
  }

  void ensureSingleQrCapacity(String qrValue) {
    if (qrValue.length > _singleQrByteModeLimit) {
      throw const FormatException(
        'This handoff contains too much information for one QR code.',
      );
    }

    try {
      QrCode.fromData(
        data: qrValue,
        errorCorrectLevel: QrErrorCorrectLevel.L,
      );
    } catch (_) {
      throw const FormatException(
        'This handoff contains too much information for one QR code.',
      );
    }
  }

  Future<Uint8List> buildQrPngBytes(
    String qrValue, {
    int size = 1200,
  }) async {
    final painter = QrPainter(
      data: qrValue,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF000000),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF000000),
      ),
      gapless: true,
    );

    final imageData = await painter.toImageData(
      size.toDouble(),
      format: ui.ImageByteFormat.png,
    );
    if (imageData == null) {
      throw const FormatException('The QR image could not be shared.');
    }
    final bytes = imageData.buffer.asUint8List();
    if (bytes.isEmpty) {
      throw const FormatException('The QR image could not be shared.');
    }
    return bytes;
  }

  Future<String?> decodeFirstQrFromImagePath(String imagePath) async {
    final controller = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );

    try {
      final capture = await controller.analyzeImage(imagePath);
      if (capture == null) return null;

      for (final barcode in capture.barcodes) {
        final raw = (barcode.rawValue ?? '').trim();
        if (raw.isNotEmpty) return raw;
      }
      return null;
    } finally {
      await controller.dispose();
    }
  }

  String sanitizeFilePart(String raw) {
    final base = raw.trim().isEmpty ? 'Job' : raw.trim();
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return sanitized.isEmpty ? 'Job' : sanitized;
  }
}
