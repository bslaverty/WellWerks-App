import 'dart:convert';

enum WellWerksPackageType {
  jobSetup,
  productionHandoff,
  drilloutHandoff,
}

class WellWerksPackageHeader {
  const WellWerksPackageHeader({
    required this.type,
    required this.fileType,
    required this.schemaVersion,
    required this.json,
  });

  final WellWerksPackageType type;
  final String fileType;
  final String schemaVersion;
  final Map<String, dynamic> json;
}

class WellWerksPackageRouterService {
  const WellWerksPackageRouterService();

  static const fileTypeJobSetup = 'wellwerks_job_setup';
  static const fileTypeLegacyActiveJob = 'wellwerks_active_job';
  static const fileTypeProductionHandoff = 'wellwerks_production_handoff';
  static const fileTypeDrilloutHandoff = 'wellwerks_drillout_handoff';

  WellWerksPackageHeader decodeHeader(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid WellWerks file format.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final fileType = (map['fileType'] as String? ?? '').trim();
    var schemaVersion = (map['schemaVersion'] as String? ?? '').trim();

    if (fileType.isEmpty) {
      throw const FormatException('Missing file type in WellWerks package.');
    }
    final isLegacyNoSchema =
        fileType == fileTypeLegacyActiveJob && schemaVersion.isEmpty;
    if (schemaVersion.isEmpty && !isLegacyNoSchema) {
      throw const FormatException(
        'Missing schema version in WellWerks package.',
      );
    }
    if (schemaVersion.isEmpty && isLegacyNoSchema) {
      schemaVersion = '1.0.0';
    }

    final type = _typeForFileType(fileType);
    if (type == null) {
      throw FormatException('Unsupported WellWerks package type: $fileType');
    }

    return WellWerksPackageHeader(
      type: type,
      fileType: fileType,
      schemaVersion: schemaVersion,
      json: map,
    );
  }

  WellWerksPackageType? _typeForFileType(String fileType) {
    switch (fileType.trim()) {
      case fileTypeJobSetup:
      case fileTypeLegacyActiveJob:
        return WellWerksPackageType.jobSetup;
      case fileTypeProductionHandoff:
        return WellWerksPackageType.productionHandoff;
      case fileTypeDrilloutHandoff:
        return WellWerksPackageType.drilloutHandoff;
      default:
        return null;
    }
  }
}
