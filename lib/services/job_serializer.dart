import '../models/job_history.dart';
import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../models/production_shift.dart';

class JobExportSnapshot {
  const JobExportSnapshot({
    required this.identityKey,
    required this.status,
    required this.company,
    required this.customer,
    required this.pad,
    required this.well,
    required this.shift,
    required this.startedDisplay,
    required this.endedDisplay,
    required this.activeJob,
    required this.endedJob,
    required this.archivedJob,
    required this.liveShift,
    required this.liveReportText,
    required this.liveTextUpdates,
    required this.liveJsa,
    required this.liveLayout,
    required this.archivedShifts,
  });

  final String identityKey;
  final String status;
  final String company;
  final String customer;
  final String pad;
  final String well;
  final String shift;
  final String startedDisplay;
  final String endedDisplay;
  final JobSetup? activeJob;
  final JobSetup? endedJob;
  final ArchivedJob? archivedJob;
  final ProductionShift? liveShift;
  final String liveReportText;
  final List<ArchivedTextUpdate> liveTextUpdates;
  final JsaDraft? liveJsa;
  final ArchivedLayoutSummary? liveLayout;
  final List<ArchivedShiftEntry> archivedShifts;
}

class JobSerializer {
  const JobSerializer();

  Map<String, dynamic> serialize({
    required JobExportSnapshot snapshot,
    required String appVersion,
    required String schemaVersion,
    required DateTime exportDate,
  }) {
    final latestShift = snapshot.liveShift ??
        (snapshot.archivedShifts.isEmpty
            ? null
            : (List<ArchivedShiftEntry>.from(snapshot.archivedShifts)
                  ..sort((a, b) => b.archivedAt.compareTo(a.archivedAt)))
                .first
                .productionShift);

    return {
      'packageType': 'wellwerks_job_package',
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'exportDate': exportDate.toIso8601String(),
      'job': {
        'identityKey': snapshot.identityKey,
        'status': snapshot.status,
        'summary': {
          'company': snapshot.company,
          'customer': snapshot.customer,
          'pad': snapshot.pad,
          'well': snapshot.well,
          'shift': snapshot.shift,
          'started': snapshot.startedDisplay,
          'ended': snapshot.endedDisplay,
        },
        'jobInformation': {
          'activeJob': snapshot.activeJob?.toJson(),
          'endedJob': snapshot.endedJob?.toJson(),
          'archivedJob': snapshot.archivedJob?.toJson(),
        },
        'settings': {
          'gasUnit': latestShift?.inventory.gasUnit ?? '',
          'tankGaugeUnit': latestShift?.inventory.gaugeEntryType ?? '',
          'chokeMode': latestShift?.header.chokeType ?? '',
          'layoutProfileId': latestShift?.header.layoutProfileId ?? '',
        },
        'sections': {
          'quickRounds': _quickRounds(snapshot),
          'productionReports': _productionReports(snapshot),
          'textUpdates': _textUpdates(snapshot),
          'jsas': _jsas(snapshot),
          'layoutDrawings': _layouts(snapshot),
        },
      },
    };
  }

  List<Map<String, dynamic>> _quickRounds(JobExportSnapshot snapshot) {
    final items = <Map<String, dynamic>>[];
    if (snapshot.liveShift != null) {
      items.add({
        'source': 'active',
        'updatedAt': snapshot.liveShift!.updatedAt.toIso8601String(),
        'productionShift': snapshot.liveShift!.toJson(),
      });
    }
    for (final shift in snapshot.archivedShifts) {
      items.add({
        'source': 'archived',
        'date': shift.date,
        'archivedAt': shift.archivedAt.toIso8601String(),
        'productionShift': shift.productionShift.toJson(),
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _productionReports(JobExportSnapshot snapshot) {
    final items = <Map<String, dynamic>>[];
    if (snapshot.liveShift != null) {
      items.add({
        'source': 'active',
        'updatedAt': snapshot.liveShift!.updatedAt.toIso8601String(),
        'savedRows':
            snapshot.liveShift!.savedRows.map((row) => row.toJson()).toList(),
        'reportText': snapshot.liveReportText,
      });
    }
    for (final shift in snapshot.archivedShifts) {
      items.add({
        'source': 'archived',
        'date': shift.date,
        'archivedAt': shift.archivedAt.toIso8601String(),
        'savedRows':
            shift.productionShift.savedRows.map((row) => row.toJson()).toList(),
        'reportText': shift.productionReportText,
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _textUpdates(JobExportSnapshot snapshot) {
    final items = <Map<String, dynamic>>[];
    if (snapshot.liveTextUpdates.isNotEmpty) {
      items.add({
        'source': 'active',
        'items': snapshot.liveTextUpdates.map((item) => item.toJson()).toList(),
      });
    }
    for (final shift in snapshot.archivedShifts) {
      items.add({
        'source': 'archived',
        'date': shift.date,
        'archivedAt': shift.archivedAt.toIso8601String(),
        'items': shift.textUpdates.map((item) => item.toJson()).toList(),
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _jsas(JobExportSnapshot snapshot) {
    final items = <Map<String, dynamic>>[];
    if (snapshot.liveJsa != null) {
      items.add({
        'source': 'active',
        'draft': snapshot.liveJsa!.toJson(),
      });
    }
    for (final shift in snapshot.archivedShifts) {
      if (shift.jsaDraft == null) continue;
      items.add({
        'source': 'archived',
        'date': shift.date,
        'archivedAt': shift.archivedAt.toIso8601String(),
        'draft': shift.jsaDraft!.toJson(),
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _layouts(JobExportSnapshot snapshot) {
    final items = <Map<String, dynamic>>[];
    if (snapshot.liveLayout != null) {
      items.add({
        'source': 'active',
        'layout': snapshot.liveLayout!.toJson(),
      });
    }
    final archivedLayout = snapshot.archivedJob?.layoutSummary;
    if (archivedLayout != null) {
      items.add({
        'source': 'archived',
        'layout': archivedLayout.toJson(),
      });
    }
    return items;
  }
}
