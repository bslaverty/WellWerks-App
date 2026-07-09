import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_box_inventory.dart';

class JobBoxInventoryService {
  static const _draftKey = 'wellwerks_job_box_inventory_working_draft_v1';
  static const _recordsKey = 'wellwerks_job_box_inventory_records_v1';
  static const _hideZeroPreferenceKey =
      'wellwerks_job_box_inventory_hide_zero_v1';

  Future<Map<String, dynamic>> _loadRecordsMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_recordsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _saveRecordsMap(
    SharedPreferences prefs,
    Map<String, dynamic> records,
  ) async {
    await prefs.setString(_recordsKey, jsonEncode(records));
  }

  Future<JobBoxInventoryRecord?> loadWorkingDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return JobBoxInventoryRecord.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_draftKey);
      return null;
    }
  }

  Future<void> saveWorkingDraft(JobBoxInventoryRecord draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
  }

  Future<void> clearWorkingDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  Future<bool> loadHideZeroPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideZeroPreferenceKey) ?? false;
  }

  Future<void> saveHideZeroPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideZeroPreferenceKey, value);
  }

  Future<JobBoxInventoryRecord?> loadRecord(String recordId) async {
    final id = recordId.trim();
    if (id.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    final raw = records[id];
    if (raw is! Map) return null;
    return JobBoxInventoryRecord.fromJson(Map<String, dynamic>.from(raw))
        .copyWith(id: id);
  }

  Future<List<JobBoxInventoryRecord>> loadAllRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    final list = records.entries
        .where((entry) => entry.value is Map)
        .map(
          (entry) => JobBoxInventoryRecord.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ).copyWith(id: entry.key),
        )
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<String> saveRecord(JobBoxInventoryRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    final now = DateTime.now();
    final id = record.id.trim().isEmpty
        ? now.microsecondsSinceEpoch.toString()
        : record.id.trim();
    final next = record.copyWith(
      id: id,
      createdAt: record.id.trim().isEmpty ? now : record.createdAt,
      updatedAt: now,
    );
    records[id] = next.toJson();
    await _saveRecordsMap(prefs, records);
    return id;
  }

  Future<void> deleteRecord(String recordId) async {
    final id = recordId.trim();
    if (id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    records.remove(id);
    await _saveRecordsMap(prefs, records);

    final draft = await loadWorkingDraft();
    if (draft != null && draft.id.trim() == id) {
      await clearWorkingDraft();
    }
  }
}
