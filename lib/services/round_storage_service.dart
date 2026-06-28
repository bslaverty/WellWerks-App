import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/round_reading.dart';

class RoundStorageService {
  static const _readingsKey = 'wellwerks_round_readings';

  Future<List<RoundReading>> loadReadings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_readingsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => RoundReading.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> saveReading(RoundReading reading) async {
    final readings = await loadReadings();
    readings.insert(0, reading);
    await _saveAll(readings.take(200).toList());
  }

  Future<void> _saveAll(List<RoundReading> readings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _readingsKey,
      jsonEncode(readings.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> clearReadings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_readingsKey);
  }
}
