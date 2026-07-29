class OperationsLogEntry {
  const OperationsLogEntry({
    required this.entryId,
    required this.packageCompatibleEntryId,
    required this.workflow,
    required this.persistentJobId,
    required this.persistentWellId,
    required this.wellName,
    required this.readingTimestamp,
    required this.createdAt,
    required this.lastModifiedAt,
    required this.sourceBuildNumber,
    required this.sourceOperatorId,
    required this.sourceOperatorName,
    required this.sourceOperatorInitials,
    required this.sourceDeviceId,
    required this.isImported,
    this.importedAt,
    this.qrPackageId = '',
    this.operationStage = '',
    this.choke = '',
    this.casingPressure = '',
    this.tubingPressure = '',
    this.pumpPressure = '',
    this.pumpRate = '',
    this.returnsRate = '',
    this.waterRate = '',
    this.flowRate = '',
    this.tankLevel = '',
    this.sweepInformation = '',
    this.sandOrSolids = '',
    this.equipmentStatus = '',
    this.downtime = '',
    this.notes = '',
  });

  final String entryId;
  final String packageCompatibleEntryId;
  final String workflow;
  final String persistentJobId;
  final String persistentWellId;
  final String wellName;
  final DateTime readingTimestamp;
  final DateTime createdAt;
  final DateTime lastModifiedAt;
  final String sourceBuildNumber;
  final String sourceOperatorId;
  final String sourceOperatorName;
  final String sourceOperatorInitials;
  final String sourceDeviceId;
  final bool isImported;
  final DateTime? importedAt;
  final String qrPackageId;
  final String operationStage;
  final String choke;
  final String casingPressure;
  final String tubingPressure;
  final String pumpPressure;
  final String pumpRate;
  final String returnsRate;
  final String waterRate;
  final String flowRate;
  final String tankLevel;
  final String sweepInformation;
  final String sandOrSolids;
  final String equipmentStatus;
  final String downtime;
  final String notes;

  OperationsLogEntry copyWith({
    String? entryId,
    String? packageCompatibleEntryId,
    String? workflow,
    String? persistentJobId,
    String? persistentWellId,
    String? wellName,
    DateTime? readingTimestamp,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    String? sourceBuildNumber,
    String? sourceOperatorId,
    String? sourceOperatorName,
    String? sourceOperatorInitials,
    String? sourceDeviceId,
    bool? isImported,
    DateTime? importedAt,
    String? qrPackageId,
    String? operationStage,
    String? choke,
    String? casingPressure,
    String? tubingPressure,
    String? pumpPressure,
    String? pumpRate,
    String? returnsRate,
    String? waterRate,
    String? flowRate,
    String? tankLevel,
    String? sweepInformation,
    String? sandOrSolids,
    String? equipmentStatus,
    String? downtime,
    String? notes,
  }) {
    return OperationsLogEntry(
      entryId: entryId ?? this.entryId,
      packageCompatibleEntryId:
          packageCompatibleEntryId ?? this.packageCompatibleEntryId,
      workflow: workflow ?? this.workflow,
      persistentJobId: persistentJobId ?? this.persistentJobId,
      persistentWellId: persistentWellId ?? this.persistentWellId,
      wellName: wellName ?? this.wellName,
      readingTimestamp: readingTimestamp ?? this.readingTimestamp,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      sourceBuildNumber: sourceBuildNumber ?? this.sourceBuildNumber,
      sourceOperatorId: sourceOperatorId ?? this.sourceOperatorId,
      sourceOperatorName: sourceOperatorName ?? this.sourceOperatorName,
      sourceOperatorInitials:
          sourceOperatorInitials ?? this.sourceOperatorInitials,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      isImported: isImported ?? this.isImported,
      importedAt: importedAt ?? this.importedAt,
      qrPackageId: qrPackageId ?? this.qrPackageId,
      operationStage: operationStage ?? this.operationStage,
      choke: choke ?? this.choke,
      casingPressure: casingPressure ?? this.casingPressure,
      tubingPressure: tubingPressure ?? this.tubingPressure,
      pumpPressure: pumpPressure ?? this.pumpPressure,
      pumpRate: pumpRate ?? this.pumpRate,
      returnsRate: returnsRate ?? this.returnsRate,
      waterRate: waterRate ?? this.waterRate,
      flowRate: flowRate ?? this.flowRate,
      tankLevel: tankLevel ?? this.tankLevel,
      sweepInformation: sweepInformation ?? this.sweepInformation,
      sandOrSolids: sandOrSolids ?? this.sandOrSolids,
      equipmentStatus: equipmentStatus ?? this.equipmentStatus,
      downtime: downtime ?? this.downtime,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entryId': entryId,
        'packageCompatibleEntryId': packageCompatibleEntryId,
        'workflow': workflow,
        'persistentJobId': persistentJobId,
        'persistentWellId': persistentWellId,
        'wellName': wellName,
        'readingTimestamp': readingTimestamp.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'sourceBuildNumber': sourceBuildNumber,
        'sourceOperatorId': sourceOperatorId,
        'sourceOperatorName': sourceOperatorName,
        'sourceOperatorInitials': sourceOperatorInitials,
        'sourceDeviceId': sourceDeviceId,
        'isImported': isImported,
        'importedAt': importedAt?.toIso8601String(),
        'qrPackageId': qrPackageId,
        'operationStage': operationStage,
        'choke': choke,
        'casingPressure': casingPressure,
        'tubingPressure': tubingPressure,
        'pumpPressure': pumpPressure,
        'pumpRate': pumpRate,
        'returnsRate': returnsRate,
        'waterRate': waterRate,
        'flowRate': flowRate,
        'tankLevel': tankLevel,
        'sweepInformation': sweepInformation,
        'sandOrSolids': sandOrSolids,
        'equipmentStatus': equipmentStatus,
        'downtime': downtime,
        'notes': notes,
      };

  factory OperationsLogEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String key) {
      return DateTime.tryParse(json[key] as String? ?? '') ?? DateTime.now();
    }

    return OperationsLogEntry(
      entryId: (json['entryId'] as String? ?? '').trim(),
      packageCompatibleEntryId:
          (json['packageCompatibleEntryId'] as String? ?? '').trim(),
      workflow: (json['workflow'] as String? ?? '').trim(),
      persistentJobId: (json['persistentJobId'] as String? ?? '').trim(),
      persistentWellId: (json['persistentWellId'] as String? ?? '').trim(),
      wellName: (json['wellName'] as String? ?? '').trim(),
      readingTimestamp: parseDate('readingTimestamp'),
      createdAt: parseDate('createdAt'),
      lastModifiedAt: parseDate('lastModifiedAt'),
      sourceBuildNumber: (json['sourceBuildNumber'] as String? ?? '').trim(),
      sourceOperatorId: (json['sourceOperatorId'] as String? ?? '').trim(),
      sourceOperatorName: (json['sourceOperatorName'] as String? ?? '').trim(),
      sourceOperatorInitials:
          (json['sourceOperatorInitials'] as String? ?? '').trim(),
      sourceDeviceId: (json['sourceDeviceId'] as String? ?? '').trim(),
      isImported: json['isImported'] as bool? ?? false,
      importedAt: DateTime.tryParse(json['importedAt'] as String? ?? ''),
      qrPackageId: (json['qrPackageId'] as String? ?? '').trim(),
      operationStage: (json['operationStage'] as String? ?? '').trim(),
      choke: (json['choke'] as String? ?? '').trim(),
      casingPressure: (json['casingPressure'] as String? ?? '').trim(),
      tubingPressure: (json['tubingPressure'] as String? ?? '').trim(),
      pumpPressure: (json['pumpPressure'] as String? ?? '').trim(),
      pumpRate: (json['pumpRate'] as String? ?? '').trim(),
      returnsRate: (json['returnsRate'] as String? ?? '').trim(),
      waterRate: (json['waterRate'] as String? ?? '').trim(),
      flowRate: (json['flowRate'] as String? ?? '').trim(),
      tankLevel: (json['tankLevel'] as String? ?? '').trim(),
      sweepInformation: (json['sweepInformation'] as String? ?? '').trim(),
      sandOrSolids: (json['sandOrSolids'] as String? ?? '').trim(),
      equipmentStatus: (json['equipmentStatus'] as String? ?? '').trim(),
      downtime: (json['downtime'] as String? ?? '').trim(),
      notes: (json['notes'] as String? ?? '').trim(),
    );
  }
}

class OperationsLogPackage {
  const OperationsLogPackage({
    required this.fileType,
    required this.schemaVersion,
    required this.packageType,
    required this.packageId,
    required this.createdAt,
    required this.sourceBuildNumber,
    required this.sourceOperatorId,
    required this.sourceOperatorName,
    required this.sourceOperatorInitials,
    required this.sourceDeviceId,
    required this.persistentJobId,
    required this.workflow,
    required this.entries,
  });

  final String fileType;
  final String schemaVersion;
  final String packageType;
  final String packageId;
  final String createdAt;
  final String sourceBuildNumber;
  final String sourceOperatorId;
  final String sourceOperatorName;
  final String sourceOperatorInitials;
  final String sourceDeviceId;
  final String persistentJobId;
  final String workflow;
  final List<OperationsLogEntry> entries;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fileType': fileType,
        'schemaVersion': schemaVersion,
        'packageType': packageType,
        'packageId': packageId,
        'createdAt': createdAt,
        'sourceBuildNumber': sourceBuildNumber,
        'sourceOperatorId': sourceOperatorId,
        'sourceOperatorName': sourceOperatorName,
        'sourceOperatorInitials': sourceOperatorInitials,
        'sourceDeviceId': sourceDeviceId,
        'persistentJobId': persistentJobId,
        'workflow': workflow,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  factory OperationsLogPackage.fromJson(Map<String, dynamic> json) {
    return OperationsLogPackage(
      fileType: (json['fileType'] as String? ?? '').trim(),
      schemaVersion: (json['schemaVersion'] as String? ?? '').trim(),
      packageType: (json['packageType'] as String? ?? '').trim(),
      packageId: (json['packageId'] as String? ?? '').trim(),
      createdAt: (json['createdAt'] as String? ?? '').trim(),
      sourceBuildNumber: (json['sourceBuildNumber'] as String? ?? '').trim(),
      sourceOperatorId: (json['sourceOperatorId'] as String? ?? '').trim(),
      sourceOperatorName: (json['sourceOperatorName'] as String? ?? '').trim(),
      sourceOperatorInitials:
          (json['sourceOperatorInitials'] as String? ?? '').trim(),
      sourceDeviceId: (json['sourceDeviceId'] as String? ?? '').trim(),
      persistentJobId: (json['persistentJobId'] as String? ?? '').trim(),
      workflow: (json['workflow'] as String? ?? '').trim(),
      entries: ((json['entries'] as List?) ?? const [])
          .map((item) => OperationsLogEntry.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}
