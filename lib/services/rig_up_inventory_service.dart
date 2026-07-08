import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RigUpInventoryService {
  static const _recordsKey = 'wellwerks_rig_up_inventory_records_v2';

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

  Future<Map<String, dynamic>?> loadRecord(String recordId) async {
    final id = recordId.trim();
    if (id.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);
    final raw = records[id];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw)..putIfAbsent('id', () => id);
  }

  Future<List<Map<String, dynamic>>> loadAllRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);

    final list = records.entries
        .where((entry) => entry.value is Map)
        .map(
          (entry) => Map<String, dynamic>.from(entry.value as Map)
            ..putIfAbsent('id', () => entry.key),
        )
        .toList();

    list.sort((a, b) {
      final aUpdated = a['updatedAt']?.toString() ?? '';
      final bUpdated = b['updatedAt']?.toString() ?? '';
      return bUpdated.compareTo(aUpdated);
    });

    return list;
  }

  Future<String> saveRecord({
    String? recordId,
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _loadRecordsMap(prefs);

    final now = DateTime.now().toIso8601String();
    final id = (recordId ?? '').trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : recordId!.trim();

    final nextPayload = Map<String, dynamic>.from(payload)
      ..['id'] = id
      ..['updatedAt'] = now;
    nextPayload.putIfAbsent('createdAt', () => now);

    records[id] = nextPayload;
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
  }
}
