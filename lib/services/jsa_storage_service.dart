import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/jsa_draft.dart';

class JsaStorageService {
  static const _draftKey = 'wellwerks_jsa_latest_draft';
  static const _recordsKey = 'wellwerks_jsa_records_v2';

  String _todayDateText() {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day);
    return local.toIso8601String().split('T').first;
  }

  String _recordKey({required String activeJobId, required String date}) {
    final normalizedJobId =
        activeJobId.trim().isEmpty ? '__no_active_job__' : activeJobId.trim();
    final normalizedDate = date.trim().isEmpty ? _todayDateText() : date.trim();
    return '$normalizedJobId|$normalizedDate';
  }

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

  Future<void> saveDraft(JsaDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
    final records = await _loadRecordsMap(prefs);
    records[_recordKey(activeJobId: draft.activeJobId, date: draft.date)] =
        draft.toJson();
    await _saveRecordsMap(prefs, records);
  }

  Future<JsaDraft?> loadDraft({String? activeJobId, String? date}) async {
    final prefs = await SharedPreferences.getInstance();
    if ((activeJobId ?? '').trim().isNotEmpty ||
        (date ?? '').trim().isNotEmpty) {
      final records = await _loadRecordsMap(prefs);
      final keyed = records[_recordKey(
        activeJobId: activeJobId ?? '',
        date: date ?? '',
      )];
      if (keyed is Map) {
        return JsaDraft.fromJson(Map<String, dynamic>.from(keyed));
      }
    }
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return null;
    return JsaDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<JsaDraft?> loadTodayForJob(String activeJobId) {
    return loadDraft(activeJobId: activeJobId, date: _todayDateText());
  }

  Future<List<JsaDraft>> loadAllDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    final drafts = records.values
        .whereType<Map>()
        .map((item) => JsaDraft.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    drafts.sort((a, b) {
      final aStamp = '${a.date.trim()} ${a.time.trim()}';
      final bStamp = '${b.date.trim()} ${b.time.trim()}';
      return bStamp.compareTo(aStamp);
    });
    return drafts;
  }

  Future<bool> hasDraftForJobDate({
    required String activeJobId,
    required String date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    return records.containsKey(
      _recordKey(activeJobId: activeJobId, date: date),
    );
  }

  Future<void> deleteDraft({
    required String activeJobId,
    required String date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    records.remove(_recordKey(activeJobId: activeJobId, date: date));
    await _saveRecordsMap(prefs, records);

    final latest = await loadDraft();
    if (latest != null &&
        _recordKey(activeJobId: latest.activeJobId, date: latest.date) ==
            _recordKey(activeJobId: activeJobId, date: date)) {
      await prefs.remove(_draftKey);
    }
  }

  Future<void> deleteDraftsForJob(String activeJobId) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    final prefix =
        _recordKey(activeJobId: activeJobId, date: '').split('|').first;
    records.removeWhere((key, value) => key.startsWith('$prefix|'));
    await _saveRecordsMap(prefs, records);

    final latest = await loadDraft();
    if (latest != null && latest.activeJobId == activeJobId) {
      await prefs.remove(_draftKey);
    }
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}
