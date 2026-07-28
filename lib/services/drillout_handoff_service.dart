import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/job_setup.dart';

class DrilloutHandoffPackage {
  const DrilloutHandoffPackage({
    required this.fileType,
    required this.schemaVersion,
    required this.appVersion,
    required this.buildNumber,
    required this.handoffId,
    required this.exportedAt,
    required this.sourceJobId,
    required this.workflow,
    required this.customer,
    required this.jobName,
    required this.jobData,
  });

  final String fileType;
  final String schemaVersion;
  final String appVersion;
  final String buildNumber;
  final String handoffId;
  final String exportedAt;
  final String sourceJobId;
  final String workflow;
  final String customer;
  final String jobName;
  final Map<String, dynamic> jobData;

  Map<String, dynamic> toJson() {
    return {
      'fileType': fileType,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'handoffId': handoffId,
      'exportedAt': exportedAt,
      'sourceJobId': sourceJobId,
      'workflow': workflow,
      'customer': customer,
      'jobName': jobName,
      'jobData': jobData,
    };
  }

  factory DrilloutHandoffPackage.fromJson(Map<String, dynamic> json) {
    return DrilloutHandoffPackage(
      fileType: json['fileType'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      buildNumber: json['buildNumber'] as String? ?? '',
      handoffId: json['handoffId'] as String? ?? '',
      exportedAt: json['exportedAt'] as String? ?? '',
      sourceJobId: json['sourceJobId'] as String? ?? '',
      workflow: json['workflow'] as String? ?? 'drillout',
      customer: json['customer'] as String? ?? '',
      jobName: json['jobName'] as String? ?? '',
      jobData: Map<String, dynamic>.from((json['jobData'] as Map?) ?? {}),
    );
  }
}

class DrilloutHandoffService {
  static const currentSchemaVersion = '1.0.0';
  static const currentFileType = 'wellwerks_drillout_handoff';

  Future<DrilloutHandoffPackage> buildPackage({
    required JobSetup activeJob,
    String? handoffId,
    DateTime? now,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final stamp = now ?? DateTime.now();
    final workflow = _normalizedWorkflow(activeJob.workflow);

    return DrilloutHandoffPackage(
      fileType: currentFileType,
      schemaVersion: currentSchemaVersion,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      handoffId: handoffId ??
          'drillout_handoff_${stamp.microsecondsSinceEpoch}_${activeJob.id}',
      exportedAt: stamp.toIso8601String(),
      sourceJobId: activeJob.id.trim(),
      workflow: workflow,
      customer: activeJob.company,
      jobName: activeJob.padName,
      jobData: activeJob.toJson(),
    );
  }

  String encodePackage(DrilloutHandoffPackage package) {
    return jsonEncode(package.toJson());
  }

  DrilloutHandoffPackage decodePackage(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid drillout handoff file format.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final fileType = map['fileType'] as String? ?? '';
    if (fileType != currentFileType) {
      throw const FormatException('Unsupported drillout handoff file type.');
    }

    final schemaVersion = map['schemaVersion'] as String? ?? '';
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException(
          'Unsupported drillout handoff schema version.');
    }

    return DrilloutHandoffPackage.fromJson(map);
  }

  JobSetup importAsActiveJob(DrilloutHandoffPackage package) {
    final imported = JobSetup.fromJson(package.jobData);
    return imported.copyWith(
      workflow: _normalizedWorkflow(
          imported.workflow.isEmpty ? package.workflow : imported.workflow),
      status: 'active',
      endedAt: null,
      startedAt: imported.startedAt ?? DateTime.now(),
    );
  }

  String _normalizedWorkflow(String workflow) {
    final normalized = workflow.trim().toLowerCase();
    if (normalized == 'cleanout') return 'cleanout';
    return 'drillout';
  }
}
