import 'job_setup.dart';
import 'jsa_draft.dart';
import 'production_shift.dart';

class ArchivedLayoutSummary {
  const ArchivedLayoutSummary({
    required this.name,
    required this.itemCount,
  });

  final String name;
  final int itemCount;

  factory ArchivedLayoutSummary.fromJson(Map<String, dynamic> json) {
    return ArchivedLayoutSummary(
      name: json['name'] as String? ?? '',
      itemCount: json['itemCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'itemCount': itemCount,
      };
}

class ArchivedTextUpdate {
  const ArchivedTextUpdate({
    required this.hourIndex,
    required this.time,
    required this.content,
  });

  final int hourIndex;
  final String time;
  final String content;

  factory ArchivedTextUpdate.fromJson(Map<String, dynamic> json) {
    return ArchivedTextUpdate(
      hourIndex: json['hourIndex'] as int? ?? 0,
      time: json['time'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'hourIndex': hourIndex,
        'time': time,
        'content': content,
      };
}

class ArchivedShiftEntry {
  const ArchivedShiftEntry({
    required this.id,
    required this.date,
    required this.productionShift,
    required this.productionReportText,
    required this.textUpdates,
    required this.archivedAt,
    this.jsaDraft,
  });

  final String id;
  final String date;
  final ProductionShift productionShift;
  final String productionReportText;
  final List<ArchivedTextUpdate> textUpdates;
  final JsaDraft? jsaDraft;
  final DateTime archivedAt;

  factory ArchivedShiftEntry.fromJson(Map<String, dynamic> json) {
    return ArchivedShiftEntry(
      id: json['id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      productionShift: ProductionShift.fromJson(
        Map<String, dynamic>.from(
          (json['productionShift'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      productionReportText: json['productionReportText'] as String? ?? '',
      textUpdates: ((json['textUpdates'] as List?) ?? const [])
          .map((item) => ArchivedTextUpdate.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
      jsaDraft: json['jsaDraft'] is Map
          ? JsaDraft.fromJson(
              Map<String, dynamic>.from(json['jsaDraft'] as Map),
            )
          : null,
      archivedAt: DateTime.tryParse(json['archivedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'productionShift': productionShift.toJson(),
        'productionReportText': productionReportText,
        'textUpdates': textUpdates.map((item) => item.toJson()).toList(),
        'jsaDraft': jsaDraft?.toJson(),
        'archivedAt': archivedAt.toIso8601String(),
      };
}

class ArchivedJob {
  const ArchivedJob({
    required this.id,
    required this.company,
    required this.padName,
    required this.dateRangeStart,
    required this.dateRangeEnd,
    required this.wells,
    required this.shifts,
    required this.updatedAt,
    this.jobSetup,
    this.layoutSummary,
  });

  final String id;
  final String company;
  final String padName;
  final String dateRangeStart;
  final String dateRangeEnd;
  final List<String> wells;
  final JobSetup? jobSetup;
  final ArchivedLayoutSummary? layoutSummary;
  final List<ArchivedShiftEntry> shifts;
  final DateTime updatedAt;

  factory ArchivedJob.fromJson(Map<String, dynamic> json) {
    return ArchivedJob(
      id: json['id'] as String? ?? '',
      company: json['company'] as String? ?? '',
      padName: json['padName'] as String? ?? '',
      dateRangeStart: json['dateRangeStart'] as String? ?? '',
      dateRangeEnd: json['dateRangeEnd'] as String? ?? '',
      wells: ((json['wells'] as List?) ?? const [])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      jobSetup: json['jobSetup'] is Map
          ? JobSetup.fromJson(
              Map<String, dynamic>.from(json['jobSetup'] as Map),
            )
          : null,
      layoutSummary: json['layoutSummary'] is Map
          ? ArchivedLayoutSummary.fromJson(
              Map<String, dynamic>.from(json['layoutSummary'] as Map),
            )
          : null,
      shifts: ((json['shifts'] as List?) ?? const [])
          .map((item) => ArchivedShiftEntry.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ArchivedJob copyWith({
    String? id,
    String? company,
    String? padName,
    String? dateRangeStart,
    String? dateRangeEnd,
    List<String>? wells,
    JobSetup? jobSetup,
    bool clearJobSetup = false,
    ArchivedLayoutSummary? layoutSummary,
    bool clearLayoutSummary = false,
    List<ArchivedShiftEntry>? shifts,
    DateTime? updatedAt,
  }) {
    return ArchivedJob(
      id: id ?? this.id,
      company: company ?? this.company,
      padName: padName ?? this.padName,
      dateRangeStart: dateRangeStart ?? this.dateRangeStart,
      dateRangeEnd: dateRangeEnd ?? this.dateRangeEnd,
      wells: wells ?? this.wells,
      jobSetup: clearJobSetup ? null : (jobSetup ?? this.jobSetup),
      layoutSummary:
          clearLayoutSummary ? null : (layoutSummary ?? this.layoutSummary),
      shifts: shifts ?? this.shifts,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'company': company,
        'padName': padName,
        'dateRangeStart': dateRangeStart,
        'dateRangeEnd': dateRangeEnd,
        'wells': wells,
        'jobSetup': jobSetup?.toJson(),
        'layoutSummary': layoutSummary?.toJson(),
        'shifts': shifts.map((item) => item.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
