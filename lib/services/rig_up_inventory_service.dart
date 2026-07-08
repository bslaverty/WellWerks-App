import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RigUpInventoryService {
  static const _recordsKey = 'wellwerks_rig_up_inventory_v1';

  String _jobKey(String activeJobId) {
    final trimmed = activeJobId.trim();
    return trimmed.isEmpty ? '__no_active_job__' : trimmed;
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

  Future<Map<String, dynamic>?> loadForJob(String activeJobId) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    final raw = records[_jobKey(activeJobId)];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  Future<void> saveForJob({
    required String activeJobId,
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    records[_jobKey(activeJobId)] = payload;
    await _saveRecordsMap(prefs, records);
  }
}
