import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import 'job_setup_qr_service.dart';

typedef QrShareExecutor = Future<ShareResult> Function(
  List<XFile> files, {
  String? subject,
  String? text,
  Rect? sharePositionOrigin,
});

typedef QrTempDirectoryProvider = Future<Directory> Function();
typedef QrPngBytesBuilder = Future<Uint8List> Function(
  String qrValue, {
  int size,
});
typedef QrFileSaver = Future<File> Function(
  Uint8List bytes,
  String fileName,
);

class WellWerksQrTransferService {
  static const int _singleQrByteModeLimit = 2953;
  static const int _minQrImageSize = 1200;

  const WellWerksQrTransferService({
    JobSetupQrService? payloadCodec,
    QrShareExecutor? shareExecutor,
    QrTempDirectoryProvider? temporaryDirectoryProvider,
    QrPngBytesBuilder? qrPngBytesBuilder,
    QrFileSaver? fileSaver,
  })  : _payloadCodec = payloadCodec ?? const JobSetupQrService(),
        _shareExecutor = shareExecutor,
        _temporaryDirectoryProvider = temporaryDirectoryProvider,
        _qrPngBytesBuilder = qrPngBytesBuilder,
        _fileSaver = fileSaver;

  final JobSetupQrService _payloadCodec;
  final QrShareExecutor? _shareExecutor;
  final QrTempDirectoryProvider? _temporaryDirectoryProvider;
  final QrPngBytesBuilder? _qrPngBytesBuilder;
  final QrFileSaver? _fileSaver;

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
    final imageSize = size < _minQrImageSize ? _minQrImageSize : size;
    final code = QrCode.fromData(
      data: qrValue,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final qrImage = QrImage(code);
    final modules = qrImage.moduleCount;
    const quietZoneModules = 4;
    final totalModules = modules + (quietZoneModules * 2);
    final cellSize = (imageSize / totalModules).floor();
    if (cellSize <= 0) {
      throw const FormatException('The QR image could not be shared.');
    }

    final renderSize = cellSize * totalModules;
    final offset = ((imageSize - renderSize) / 2).floor();
    final image = img.Image(width: imageSize, height: imageSize);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (!qrImage.isDark(row, col)) continue;
        final left = offset + ((col + quietZoneModules) * cellSize);
        final top = offset + ((row + quietZoneModules) * cellSize);
        img.fillRect(
          image,
          x1: left,
          y1: top,
          x2: left + cellSize - 1,
          y2: top + cellSize - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  Future<File> saveQrPngFile(
    String qrValue, {
    required String fileName,
    int size = 1200,
  }) async {
    final pngBuilder = _qrPngBytesBuilder ?? buildQrPngBytes;
    final bytes = await pngBuilder(qrValue, size: size);
    final customFileSaver = _fileSaver;
    if (customFileSaver != null) {
      return customFileSaver(bytes, _normalizePngFileName(fileName));
    }
    final directory =
        await (_temporaryDirectoryProvider ?? getTemporaryDirectory)();
    final safeName = _normalizePngFileName(fileName);
    final file = File('${directory.path}/$safeName');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<ShareResult> shareQrPng({
    required String qrValue,
    required String fileName,
    BuildContext? shareContext,
    String? subject,
    String? text,
    int size = 1200,
  }) async {
    final origin =
        shareContext == null ? null : _sharePositionOriginFor(shareContext);
    final file = await saveQrPngFile(
      qrValue,
      fileName: fileName,
      size: size,
    );
    final executor = _shareExecutor ?? _defaultShareExecutor;
    return executor(
      <XFile>[XFile(file.path, mimeType: 'image/png')],
      subject: subject,
      text: text,
      sharePositionOrigin: origin,
    );
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

  Future<ShareResult> _defaultShareExecutor(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
  }) {
    return Share.shareXFiles(
      files,
      subject: subject,
      text: text,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Rect? _sharePositionOriginFor(BuildContext context) {
    try {
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final offset = renderObject.localToGlobal(Offset.zero);
        return offset & renderObject.size;
      }

      final size = MediaQuery.sizeOf(context);
      if (size.width <= 0 || size.height <= 0) {
        return null;
      }
      return Rect.fromLTWH(0, 0, size.width, size.height);
    } catch (_) {
      return null;
    }
  }

  String _normalizePngFileName(String raw) {
    final trimmed = raw.trim();
    final base = trimmed.toLowerCase().endsWith('.png')
        ? trimmed.substring(0, trimmed.length - 4)
        : trimmed;
    final safeBase = sanitizeFilePart(base);
    return '$safeBase.png';
  }
}
