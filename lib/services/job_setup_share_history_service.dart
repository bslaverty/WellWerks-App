import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class JobSetupShareHistoryEntry {
  const JobSetupShareHistoryEntry({
    required this.packageId,
    required this.packageType,
    required this.sourceJobId,
    required this.jobLabel,
    required this.timestampIso,
    required this.direction,
    required this.method,
    required this.status,
    required this.resultSummary,
  });

  final String packageId;
  final String packageType;
  final String sourceJobId;
  final String jobLabel;
  final String timestampIso;
  final String direction;
  final String method;
  final String status;
  final String resultSummary;

  Map<String, dynamic> toJson() {
    return {
      'packageId': packageId,
      'packageType': packageType,
      'sourceJobId': sourceJobId,
      'jobLabel': jobLabel,
      'timestampIso': timestampIso,
      'direction': direction,
      'method': method,
      'status': status,
      'resultSummary': resultSummary,
    };
  }

  factory JobSetupShareHistoryEntry.fromJson(Map<String, dynamic> json) {
    return JobSetupShareHistoryEntry(
      packageId: json['packageId'] as String? ?? '',
      packageType: json['packageType'] as String? ?? '',
      sourceJobId: json['sourceJobId'] as String? ?? '',
      jobLabel: json['jobLabel'] as String? ?? '',
      timestampIso: json['timestampIso'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
      method: json['method'] as String? ?? '',
      status: json['status'] as String? ?? '',
      resultSummary: json['resultSummary'] as String? ?? '',
    );
  }
}

class JobSetupShareHistoryService {
  const JobSetupShareHistoryService();

  static const _historyKey = 'wellwerks_job_setup_share_history_v1';
  static const _maxEntries = 100;

  Future<List<JobSetupShareHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <JobSetupShareHistoryEntry>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => JobSetupShareHistoryEntry.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false);
    } catch (_) {
      return const <JobSetupShareHistoryEntry>[];
    }
  }

  Future<void> appendEntry(JobSetupShareHistoryEntry entry) async {
    final current = await loadHistory();
    final next = <JobSetupShareHistoryEntry>[entry, ...current]
        .take(_maxEntries)
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }
}
