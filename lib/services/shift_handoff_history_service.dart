import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ShiftHandoffHistoryEntry {
  const ShiftHandoffHistoryEntry({
    required this.action,
    required this.timestampIso,
    required this.handoffId,
    required this.sourceJobId,
    required this.entriesAdded,
    required this.duplicatesSkipped,
    required this.conflictCount,
    required this.importedConflictChoices,
  });

  final String action;
  final String timestampIso;
  final String handoffId;
  final String sourceJobId;
  final int entriesAdded;
  final int duplicatesSkipped;
  final int conflictCount;
  final int importedConflictChoices;

  Map<String, dynamic> toJson() {
    return {
      'action': action,
      'timestampIso': timestampIso,
      'handoffId': handoffId,
      'sourceJobId': sourceJobId,
      'entriesAdded': entriesAdded,
      'duplicatesSkipped': duplicatesSkipped,
      'conflictCount': conflictCount,
      'importedConflictChoices': importedConflictChoices,
    };
  }

  factory ShiftHandoffHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ShiftHandoffHistoryEntry(
      action: json['action'] as String? ?? '',
      timestampIso: json['timestampIso'] as String? ?? '',
      handoffId: json['handoffId'] as String? ?? '',
      sourceJobId: json['sourceJobId'] as String? ?? '',
      entriesAdded: (json['entriesAdded'] as num?)?.toInt() ?? 0,
      duplicatesSkipped: (json['duplicatesSkipped'] as num?)?.toInt() ?? 0,
      conflictCount: (json['conflictCount'] as num?)?.toInt() ?? 0,
      importedConflictChoices:
          (json['importedConflictChoices'] as num?)?.toInt() ?? 0,
    );
  }
}

class ShiftHandoffHistoryService {
  static const _historyKey = 'wellwerks_shift_handoff_history_v1';
  static const _maxEntries = 100;

  Future<List<ShiftHandoffHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <ShiftHandoffHistoryEntry>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final entries = decoded
          .map((item) => ShiftHandoffHistoryEntry.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false);
      final sorted = List<ShiftHandoffHistoryEntry>.from(entries)
        ..sort((a, b) {
          final aTime = DateTime.tryParse(a.timestampIso);
          final bTime = DateTime.tryParse(b.timestampIso);
          if (aTime != null && bTime != null) {
            return bTime.compareTo(aTime);
          }
          return b.timestampIso.compareTo(a.timestampIso);
        });
      return sorted;
    } catch (_) {
      return const <ShiftHandoffHistoryEntry>[];
    }
  }

  Future<void> appendEntry(ShiftHandoffHistoryEntry entry) async {
    final existing = await loadHistory();
    final next = <ShiftHandoffHistoryEntry>[entry, ...existing]..sort((a, b) {
        final aTime = DateTime.tryParse(a.timestampIso);
        final bTime = DateTime.tryParse(b.timestampIso);
        if (aTime != null && bTime != null) {
          return bTime.compareTo(aTime);
        }
        return b.timestampIso.compareTo(a.timestampIso);
      });

    final limited = next.take(_maxEntries).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(limited.map((item) => item.toJson()).toList()),
    );
  }
}
