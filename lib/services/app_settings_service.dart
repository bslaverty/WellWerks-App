import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/job_history_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/production_shift_service.dart';

class AppSettingsData {
  const AppSettingsData({
    required this.defaultGasUnit,
    required this.defaultGaugeType,
    required this.defaultBblPerInch,
  });

  final String defaultGasUnit;
  final String defaultGaugeType;
  final String defaultBblPerInch;

  AppSettingsData copyWith({
    String? defaultGasUnit,
    String? defaultGaugeType,
    String? defaultBblPerInch,
  }) {
    return AppSettingsData(
      defaultGasUnit: defaultGasUnit ?? this.defaultGasUnit,
      defaultGaugeType: defaultGaugeType ?? this.defaultGaugeType,
      defaultBblPerInch: defaultBblPerInch ?? this.defaultBblPerInch,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultGasUnit': defaultGasUnit,
        'defaultGaugeType': defaultGaugeType,
        'defaultBblPerInch': defaultBblPerInch,
      };

  factory AppSettingsData.fromJson(Map<String, dynamic> json) {
    return AppSettingsData(
      defaultGasUnit: _normalizeGasUnit(json['defaultGasUnit'] as String?),
      defaultGaugeType:
          _normalizeGaugeType(json['defaultGaugeType'] as String?),
      defaultBblPerInch:
          _normalizeBblPerInch(json['defaultBblPerInch'] as String?),
    );
  }

  static String _normalizeGasUnit(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'mmcfd' ? 'mmcfd' : 'mcfd';
  }

  static String _normalizeGaugeType(String? value) {
    switch ((value ?? '').trim()) {
      case 'feetInches':
        return 'feetInches';
      case 'decimalFeet':
        return 'decimalFeet';
      default:
        return 'inches';
    }
  }

  static String _normalizeBblPerInch(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed <= 0) return '1.67';
    return parsed % 1 == 0 ? parsed.toStringAsFixed(0) : parsed.toString();
  }
}

class AppSettingsService {
  static const _settingsKey = 'wellwerks_app_settings_v1';

  final ProductionShiftService _shiftService = ProductionShiftService();
  final JobStorageService _jobStorage = JobStorageService();
  final JsaStorageService _jsaStorage = JsaStorageService();
  final JobHistoryService _historyService = JobHistoryService();

  Future<AppSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      return const AppSettingsData(
        defaultGasUnit: 'mcfd',
        defaultGaugeType: 'inches',
        defaultBblPerInch: '1.67',
      );
    }
    try {
      return AppSettingsData.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>),
      );
    } catch (_) {
      return const AppSettingsData(
        defaultGasUnit: 'mcfd',
        defaultGaugeType: 'inches',
        defaultBblPerInch: '1.67',
      );
    }
  }

  Future<void> save(AppSettingsData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(data.toJson()));
  }

  Future<void> clearActiveData() async {
    await _shiftService.clearActiveShift();
    await _jobStorage.clearActiveJob();
    await _jsaStorage.clearDraft();
  }

  Future<void> clearHistory() async {
    await _historyService.saveHistory(const []);
  }
}
