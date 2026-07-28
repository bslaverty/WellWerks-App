import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/job_setup.dart';

class ActiveJobSharePackage {
  const ActiveJobSharePackage({
    required this.fileType,
    required this.schemaVersion,
    required this.appVersion,
    required this.buildNumber,
    required this.exportedAt,
    required this.sourceJobId,
    required this.workflow,
    required this.jobData,
  });

  final String fileType;
  final String schemaVersion;
  final String appVersion;
  final String buildNumber;
  final String exportedAt;
  final String sourceJobId;
  final String workflow;
  final Map<String, dynamic> jobData;

  Map<String, dynamic> toJson() {
    return {
      'fileType': fileType,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'exportedAt': exportedAt,
      'sourceJobId': sourceJobId,
      'workflow': workflow,
      'jobData': jobData,
    };
  }

  factory ActiveJobSharePackage.fromJson(Map<String, dynamic> json) {
    return ActiveJobSharePackage(
      fileType: json['fileType'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      buildNumber: json['buildNumber'] as String? ?? '',
      exportedAt: json['exportedAt'] as String? ?? '',
      sourceJobId: json['sourceJobId'] as String? ?? '',
      workflow: json['workflow'] as String? ?? 'production',
      jobData: Map<String, dynamic>.from((json['jobData'] as Map?) ?? {}),
    );
  }
}

class ActiveJobShareService {
  static const currentSchemaVersion = '1.0.0';
  static const currentFileType = 'wellwerks_job_setup';
  static const legacyFileType = 'wellwerks_active_job';

  Future<ActiveJobSharePackage> buildPackage({
    required JobSetup activeJob,
    DateTime? now,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final stamp = now ?? DateTime.now();
    return ActiveJobSharePackage(
      fileType: currentFileType,
      schemaVersion: currentSchemaVersion,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      exportedAt: stamp.toIso8601String(),
      sourceJobId: activeJob.id.trim(),
      workflow: activeJob.workflow.trim().isEmpty
          ? 'production'
          : activeJob.workflow.trim(),
      jobData: activeJob.toJson(),
    );
  }

  String encodePackage(ActiveJobSharePackage package) {
    return jsonEncode(package.toJson());
  }

  ActiveJobSharePackage decodePackage(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid active job file format.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final fileType = map['fileType'] as String? ?? '';
    if (fileType != currentFileType && fileType != legacyFileType) {
      throw const FormatException('Unsupported active job file type.');
    }
    final schemaVersion = map['schemaVersion'] as String? ?? '';
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported active job schema version.');
    }
    return ActiveJobSharePackage.fromJson(map);
  }
}
