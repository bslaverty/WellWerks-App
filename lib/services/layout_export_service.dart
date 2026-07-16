import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/layout_interchange.dart';
import 'layout_interchange_codec.dart';

enum LayoutExportFormat { wellWerksEditable, visioSvg }

class LayoutExportException implements Exception {
  final String message;

  const LayoutExportException(this.message);

  @override
  String toString() => message;
}

class LayoutExportArtifact {
  final LayoutExportFormat format;
  final String fileName;
  final String mimeType;
  final String contents;
  final String shareSubject;
  final String shareText;

  const LayoutExportArtifact({
    required this.format,
    required this.fileName,
    required this.mimeType,
    required this.contents,
    required this.shareSubject,
    required this.shareText,
  });
}

class LayoutExportService {
  static const String fallbackFileName = 'WellWerks Layout';

  const LayoutExportService();

  String sanitizeFileName(String raw) {
    final trimmed = raw.trim();
    final base = trimmed.isEmpty ? fallbackFileName : trimmed;
    final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? fallbackFileName : sanitized;
  }

  String fileNameWithExtension(String raw, String extension) {
    final normalized = sanitizeFileName(raw);
    final suffix = '.${extension.toLowerCase()}';
    if (normalized.toLowerCase().endsWith(suffix)) {
      return normalized;
    }
    return '$normalized$suffix';
  }

  LayoutExportArtifact buildEditableArtifact(
    WellWerksLayoutInterchange model, {
    required String requestedFileName,
  }) {
    final contents = LayoutInterchangeCodec.encodeWellWerksJson(model);
    if (contents.trim().isEmpty) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } catch (_) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }
    if (decoded['format'] != WellWerksLayoutInterchange.formatName ||
        decoded['version'] != WellWerksLayoutInterchange.currentVersion) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }

    return LayoutExportArtifact(
      format: LayoutExportFormat.wellWerksEditable,
      fileName: fileNameWithExtension(requestedFileName, 'wwlayout'),
      mimeType: 'application/octet-stream',
      contents: contents,
      shareSubject: 'WellWerks Editable Layout',
      shareText: 'Editable WellWerks layout export.',
    );
  }

  LayoutExportArtifact buildSvgArtifact(
    WellWerksLayoutInterchange model, {
    required String requestedFileName,
  }) {
    final contents = LayoutInterchangeCodec.encodeVisioSvg(model);
    final trimmed = contents.trimLeft();
    if (trimmed.isEmpty || !trimmed.contains('<svg')) {
      throw const LayoutExportException('Unable to generate the Visio SVG.');
    }
    if (!(trimmed.startsWith('<?xml') || trimmed.startsWith('<svg'))) {
      throw const LayoutExportException('Unable to generate the Visio SVG.');
    }
    if (!contents.contains('wellwerks-layout-interchange')) {
      throw const LayoutExportException('Unable to generate the Visio SVG.');
    }

    return LayoutExportArtifact(
      format: LayoutExportFormat.visioSvg,
      fileName: fileNameWithExtension(requestedFileName, 'svg'),
      mimeType: 'image/svg+xml',
      contents: contents,
      shareSubject: 'WellWerks Layout SVG',
      shareText: 'Microsoft Visio SVG exported from WellWerks.',
    );
  }

  Future<File> writeTemporaryFile(
    LayoutExportArtifact artifact, {
    Directory? directory,
  }) async {
    final tempDirectory = directory ?? await getTemporaryDirectory();
    final file = File('${tempDirectory.path}/${artifact.fileName}');
    await file.writeAsString(artifact.contents, flush: true);
    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    if (!exists || length <= 0) {
      throw const LayoutExportException(
          'The export file could not be written.');
    }
    return file;
  }
}
