import 'dart:convert';

import '../models/job_setup.dart';
import 'active_job_share_service.dart';
import 'wellwerks_package_router_service.dart';

class JobSetupImportPreview {
  const JobSetupImportPreview({
    required this.package,
    required this.job,
    required this.matchingJob,
  });

  final ActiveJobSharePackage package;
  final JobSetup job;
  final JobSetup? matchingJob;

  bool get hasMatchingJob => matchingJob != null;
}

class JobSetupImportService {
  const JobSetupImportService({
    ActiveJobShareService? jobShareService,
    WellWerksPackageRouterService? router,
  })  : _jobShareService = jobShareService ?? const ActiveJobShareService(),
        _router = router ?? const WellWerksPackageRouterService();

  static const importCodePrefix = 'WELLWERKS_JOB_SETUP_V1:';

  final ActiveJobShareService _jobShareService;
  final WellWerksPackageRouterService _router;

  String buildTextShareMessage({
    required ActiveJobSharePackage package,
    required String company,
    required String padOrJob,
  }) {
    final importCode = buildImportCode(package);
    final safeCompany = company.trim().isEmpty ? '-' : company.trim();
    final safePad = padOrJob.trim().isEmpty ? '-' : padOrJob.trim();
    return [
      'WellWerks Job Setup',
      '$safeCompany - $safePad',
      'Copy the complete import code below and paste it into WellWerks.',
      '',
      importCode,
    ].join('\n');
  }

  String buildSummary(JobSetup job) {
    final wells = job.resolvedWellNames;
    final wellSummary = wells.isEmpty ? '-' : wells.join(' / ');
    final workflow = job.workflow.trim().isEmpty ? 'production' : job.workflow;
    return [
      'WellWerks Job Setup Summary',
      'Company: ${job.company.trim().isEmpty ? '-' : job.company.trim()}',
      'Pad/Job: ${job.padName.trim().isEmpty ? '-' : job.padName.trim()}',
      'Workflow: $workflow',
      'Wells: $wellSummary',
      'Shift: ${job.shift.trim().isEmpty ? '-' : job.shift.trim()}',
      'Job ID: ${job.id.trim().isEmpty ? '-' : job.id.trim()}',
    ].join('\n');
  }

  String buildImportCode(ActiveJobSharePackage package) {
    final jsonPayload = _jobShareService.encodePackage(package);
    final encoded = base64UrlEncode(utf8.encode(jsonPayload));
    if (encoded.trim().isEmpty) {
      throw const FormatException('Generated import code payload is empty.');
    }
    return '$importCodePrefix$encoded';
  }

  String extractImportCodePayload(String text) {
    final trimmed = text.trim();
    final index = trimmed.indexOf(importCodePrefix);
    if (index < 0) {
      throw const FormatException(
        'The pasted text does not contain a WellWerks Job Setup.',
      );
    }

    final payloadCandidate =
        trimmed.substring(index + importCodePrefix.length).trim();
    if (payloadCandidate.isEmpty) {
      throw const FormatException(
        'The Job Setup import code is incomplete. Copy the entire message and try again.',
      );
    }

    final extracted = _extractPayloadFromMessage(payloadCandidate);
    if (extracted == null || extracted.isEmpty) {
      throw const FormatException(
        'The Job Setup import code is incomplete. Copy the entire message and try again.',
      );
    }

    try {
      final decodedBytes = base64Url.decode(extracted);
      final decoded = utf8.decode(decodedBytes).trim();
      if (decoded.isEmpty) {
        throw const FormatException(
          'The Job Setup import code is incomplete. Copy the entire message and try again.',
        );
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'The Job Setup import code is incomplete. Copy the entire message and try again.',
      );
    }
  }

  JobSetupImportPreview decodePreview({
    required String raw,
    required List<JobSetup> localJobs,
  }) {
    final parsed = _decodeAny(raw);
    final importedJob = JobSetup.fromJson(parsed.jobData);
    final normalizedJob = importedJob.copyWith(
      workflow: importedJob.workflow.trim().isEmpty
          ? parsed.workflow
          : importedJob.workflow,
      status: importedJob.status.trim().isEmpty ? 'active' : importedJob.status,
      endedAt: null,
      startedAt: importedJob.startedAt ?? DateTime.now(),
    );

    final sourceId = parsed.sourceJobId.trim().isEmpty
        ? normalizedJob.id.trim()
        : parsed.sourceJobId.trim();
    JobSetup? matching;
    if (sourceId.isNotEmpty) {
      for (final job in localJobs) {
        if (job.id.trim() == sourceId) {
          matching = job;
          break;
        }
      }
    }

    return JobSetupImportPreview(
      package: parsed,
      job: normalizedJob,
      matchingJob: matching,
    );
  }

  JobSetup buildImportAsNew(JobSetupImportPreview preview,
      {required List<JobSetup> localJobs}) {
    final usedIds =
        localJobs.map((e) => e.id.trim()).where((e) => e.isNotEmpty).toSet();
    var candidate = preview.job;
    var sourceId = candidate.id.trim().isEmpty
        ? preview.package.sourceJobId.trim()
        : candidate.id.trim();
    if (sourceId.isEmpty) {
      sourceId = DateTime.now().microsecondsSinceEpoch.toString();
    }

    if (usedIds.contains(sourceId)) {
      sourceId = '${sourceId}_${DateTime.now().millisecondsSinceEpoch}';
    }

    candidate = candidate.copyWith(
      id: sourceId,
      startedAt: candidate.startedAt ?? DateTime.now(),
      endedAt: null,
      status: 'active',
    );
    return candidate;
  }

  JobSetup buildImportAsUpdate(JobSetupImportPreview preview) {
    final existing = preview.matchingJob;
    if (existing == null) {
      throw const FormatException('No matching local job exists for update.');
    }

    final incoming = preview.job;
    return existing.copyWith(
      company: incoming.company,
      padName: incoming.padName,
      customer: incoming.customer,
      leaseName: incoming.leaseName,
      leaseNames: incoming.leaseNames,
      county: incoming.county,
      state: incoming.state,
      crew: incoming.crew,
      shift: incoming.shift,
      dateStarted: incoming.dateStarted,
      workflow: incoming.workflow,
      drilloutSetup: incoming.drilloutSetup,
      wells: incoming.wells,
      wellEntries: incoming.wellEntries,
      wellFieldKeys: incoming.wellFieldKeys,
      activeEquipmentSections: incoming.activeEquipmentSections,
      sandSeparators: incoming.sandSeparators,
      plugCatchers: incoming.plugCatchers,
      chokeManifolds: incoming.chokeManifolds,
      lineHeaters: incoming.lineHeaters,
      testUnits: incoming.testUnits,
      ecds: incoming.ecds,
      vrus: incoming.vrus,
      flares: incoming.flares,
      transferPumps: incoming.transferPumps,
      oilTanks: incoming.oilTanks,
      oilTankCapacity: incoming.oilTankCapacity,
      waterTanks: incoming.waterTanks,
      waterTankCapacity: incoming.waterTankCapacity,
      productionTankFactor: incoming.productionTankFactor,
      selectedChemicals: incoming.selectedChemicals,
      reportTimes: incoming.reportTimes,
      startedAt: existing.startedAt ?? incoming.startedAt ?? DateTime.now(),
      endedAt: null,
      status: 'active',
    );
  }

  ActiveJobSharePackage _decodeAny(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Job Setup payload is empty.');
    }

    // Try import-code decoding first.
    if (trimmed.contains(importCodePrefix)) {
      final payload = extractImportCodePayload(trimmed);
      return _decodePackageJson(payload);
    }

    // Structured JSON package.
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return _decodePackageJson(trimmed);
    }

    throw const FormatException(
      'The pasted text does not contain a WellWerks Job Setup.',
    );
  }

  String? _extractPayloadFromMessage(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return null;

    for (var end = compact.length; end > 0; end--) {
      final candidate = compact.substring(0, end);
      if (!_looksBase64Url(candidate)) {
        continue;
      }
      try {
        final decoded = utf8.decode(base64Url.decode(candidate)).trim();
        if (decoded.startsWith('{') && decoded.endsWith('}')) {
          return candidate;
        }
      } catch (_) {
        // Keep searching for a valid payload boundary.
      }
    }

    return null;
  }

  bool _looksBase64Url(String value) {
    return RegExp(r'^[A-Za-z0-9_\-]+=*$').hasMatch(value);
  }

  ActiveJobSharePackage _decodePackageJson(String rawJson) {
    try {
      final header = _router.decodeHeader(rawJson);
      if (header.type != WellWerksPackageType.jobSetup) {
        throw const FormatException(
            'The selected file is not a WellWerks Job Setup.');
      }
      return _jobShareService.decodePackage(rawJson);
    } on FormatException {
      rethrow;
    } catch (_) {
      // Attempt legacy plain JobSetup JSON shape.
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is! Map) {
          throw const FormatException('Invalid Job Setup payload.');
        }
        final job = JobSetup.fromJson(Map<String, dynamic>.from(decoded));
        return ActiveJobSharePackage(
          fileType: ActiveJobShareService.currentFileType,
          schemaVersion: ActiveJobShareService.currentSchemaVersion,
          packageId: 'legacy_${DateTime.now().microsecondsSinceEpoch}',
          appVersion: '',
          buildNumber: '',
          packageCreatedAt: DateTime.now().toIso8601String(),
          sourceJobId: job.id,
          customer: job.company,
          jobName: job.padName,
          workflow: job.workflow.trim().isEmpty ? 'production' : job.workflow,
          wells: job.resolvedWellNames,
          wellIds: job.wellIds,
          jobData: job.toJson(),
        );
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('Invalid Job Setup payload.');
      }
    }
  }
}
