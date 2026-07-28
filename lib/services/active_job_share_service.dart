import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/job_setup.dart';

class ActiveJobSharePackage {
  const ActiveJobSharePackage({
    required this.fileType,
    required this.schemaVersion,
    this.packageId = '',
    required this.appVersion,
    required this.buildNumber,
    String? packageCreatedAt,
    String? exportedAt,
    required this.sourceJobId,
    this.customer = '',
    this.jobName = '',
    required this.workflow,
    this.wells = const [],
    this.wellIds = const [],
    required this.jobData,
  }) : packageCreatedAt = packageCreatedAt ?? exportedAt ?? '';

  final String fileType;
  final String schemaVersion;
  final String packageId;
  final String appVersion;
  final String buildNumber;
  final String packageCreatedAt;
  final String sourceJobId;
  final String customer;
  final String jobName;
  final String workflow;
  final List<String> wells;
  final List<String> wellIds;
  final Map<String, dynamic> jobData;

  Map<String, dynamic> toJson() {
    return {
      'fileType': fileType,
      'schemaVersion': schemaVersion,
      'packageId': packageId,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'packageCreatedAt': packageCreatedAt,
      // Backward compatibility key consumed by prior builds.
      'exportedAt': packageCreatedAt,
      'sourceJobId': sourceJobId,
      'customer': customer,
      'jobName': jobName,
      'workflow': workflow,
      'wells': wells,
      'wellIds': wellIds,
      'jobData': jobData,
    };
  }

  factory ActiveJobSharePackage.fromJson(Map<String, dynamic> json) {
    return ActiveJobSharePackage(
      fileType: json['fileType'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '',
      packageId: json['packageId'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      buildNumber: json['buildNumber'] as String? ?? '',
      packageCreatedAt: (json['packageCreatedAt'] as String? ?? '').isEmpty
          ? (json['exportedAt'] as String? ?? '')
          : (json['packageCreatedAt'] as String? ?? ''),
      sourceJobId: json['sourceJobId'] as String? ?? '',
      customer: json['customer'] as String? ?? '',
      jobName: json['jobName'] as String? ?? '',
      workflow: json['workflow'] as String? ?? 'production',
      wells: List<String>.from(json['wells'] as List? ?? const []),
      wellIds: List<String>.from(json['wellIds'] as List? ?? const []),
      jobData: Map<String, dynamic>.from((json['jobData'] as Map?) ?? {}),
    );
  }
}

class ActiveJobShareService {
  const ActiveJobShareService();

  static const currentSchemaVersion = '1.1.0';
  static const currentFileType = 'wellwerks_job_setup';
  static const legacyFileType = 'wellwerks_active_job';

  Future<ActiveJobSharePackage> buildPackage({
    required JobSetup activeJob,
    DateTime? now,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final stamp = now ?? DateTime.now();
    final resolvedWells = activeJob.resolvedWellNames;
    final resolvedWellIds = activeJob.wellIds;
    final sourceJobId = activeJob.id.trim();
    final packageId =
        'job_setup_${stamp.microsecondsSinceEpoch}_${sourceJobId.isEmpty ? 'new' : sourceJobId}';

    return ActiveJobSharePackage(
      fileType: currentFileType,
      schemaVersion: currentSchemaVersion,
      packageId: packageId,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      packageCreatedAt: stamp.toIso8601String(),
      sourceJobId: sourceJobId,
      customer: activeJob.company,
      jobName: activeJob.padName,
      workflow: activeJob.workflow.trim().isEmpty
          ? 'production'
          : activeJob.workflow.trim(),
      wells: resolvedWells,
      wellIds: resolvedWellIds,
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
    final isLegacyWithoutSchema =
        fileType == legacyFileType && schemaVersion.trim().isEmpty;
    final isSupportedSchema =
        schemaVersion == currentSchemaVersion || schemaVersion == '1.0.0';
    if (!isSupportedSchema && !isLegacyWithoutSchema) {
      throw const FormatException('Unsupported active job schema version.');
    }
    return ActiveJobSharePackage.fromJson(map);
  }
}
