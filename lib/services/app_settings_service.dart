import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/job_history_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/production_shift_service.dart';

class AppSettingsDefaults {
  static const gasUnit = 'mcfd';
  static const gaugeType = 'inches';
  static const bblPerInch = '1.67';
  static const gasCalculationMethod = 'accumulator';
  static const chokeDisplay = 'ADJ';
  static const optionalReportSections = [
    'vru',
    'compressor',
    'gasCooler',
    'waterCooler',
    'inventory',
    'notes',
  ];
}

class AppOptionalReportSection {
  const AppOptionalReportSection({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class AppSettingsData {
  const AppSettingsData({
    required this.defaultGasUnit,
    required this.defaultGaugeType,
    required this.defaultBblPerInch,
    required this.defaultGasCalculationMethod,
    required this.defaultChokeDisplay,
    required this.defaultOptionalReportSections,
  });

  final String defaultGasUnit;
  final String defaultGaugeType;
  final String defaultBblPerInch;
  final String defaultGasCalculationMethod;
  final String defaultChokeDisplay;
  final List<String> defaultOptionalReportSections;

  static const optionalReportSectionOptions = [
    AppOptionalReportSection(id: 'vru', label: 'VRU'),
    AppOptionalReportSection(id: 'compressor', label: 'Compressor'),
    AppOptionalReportSection(id: 'gasCooler', label: 'Gas Cooler'),
    AppOptionalReportSection(id: 'waterCooler', label: 'Water Cooler'),
    AppOptionalReportSection(id: 'inventory', label: 'Inventory'),
    AppOptionalReportSection(id: 'notes', label: 'Notes'),
  ];

  AppSettingsData copyWith({
    String? defaultGasUnit,
    String? defaultGaugeType,
    String? defaultBblPerInch,
    String? defaultGasCalculationMethod,
    String? defaultChokeDisplay,
    List<String>? defaultOptionalReportSections,
  }) {
    return AppSettingsData(
      defaultGasUnit: defaultGasUnit ?? this.defaultGasUnit,
      defaultGaugeType: defaultGaugeType ?? this.defaultGaugeType,
      defaultBblPerInch: defaultBblPerInch ?? this.defaultBblPerInch,
      defaultGasCalculationMethod:
          defaultGasCalculationMethod ?? this.defaultGasCalculationMethod,
      defaultChokeDisplay: defaultChokeDisplay ?? this.defaultChokeDisplay,
      defaultOptionalReportSections:
          defaultOptionalReportSections ?? this.defaultOptionalReportSections,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultGasUnit': defaultGasUnit,
        'defaultGaugeType': defaultGaugeType,
        'defaultBblPerInch': defaultBblPerInch,
        'defaultGasCalculationMethod': defaultGasCalculationMethod,
        'defaultChokeDisplay': defaultChokeDisplay,
        'defaultOptionalReportSections': defaultOptionalReportSections,
      };

  factory AppSettingsData.fromJson(Map<String, dynamic> json) {
    return AppSettingsData(
      defaultGasUnit: _normalizeGasUnit(json['defaultGasUnit'] as String?),
      defaultGaugeType:
          _normalizeGaugeType(json['defaultGaugeType'] as String?),
      defaultBblPerInch:
          _normalizeBblPerInch(json['defaultBblPerInch'] as String?),
      defaultGasCalculationMethod: _normalizeGasCalculationMethod(
        json['defaultGasCalculationMethod'] as String?,
      ),
      defaultChokeDisplay:
          _normalizeChokeDisplay(json['defaultChokeDisplay'] as String?),
      defaultOptionalReportSections: _normalizeOptionalSections(
        (json['defaultOptionalReportSections'] as List?)
                ?.map((item) => item?.toString() ?? '')
                .toList() ??
            const [],
      ),
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
    if (parsed == null || parsed <= 0) return AppSettingsDefaults.bblPerInch;
    return parsed % 1 == 0 ? parsed.toStringAsFixed(0) : parsed.toString();
  }

  static String _normalizeGasCalculationMethod(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'manual' ? 'manual' : 'accumulator';
  }

  static String _normalizeChokeDisplay(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return normalized == 'POS' ? 'POS' : 'ADJ';
  }

  static List<String> _normalizeOptionalSections(List<String> value) {
    final allowed = optionalReportSectionOptions.map((item) => item.id).toSet();
    final normalized = value
        .map((item) => item.trim())
        .where((item) => allowed.contains(item))
        .toSet()
        .toList();
    normalized.sort(
      (a, b) => AppSettingsDefaults.optionalReportSections
          .indexOf(a)
          .compareTo(AppSettingsDefaults.optionalReportSections.indexOf(b)),
    );
    return normalized.isEmpty
        ? List<String>.from(AppSettingsDefaults.optionalReportSections)
        : normalized;
  }

  bool isOptionalSectionEnabled(String sectionId) {
    return defaultOptionalReportSections.contains(sectionId);
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
      return _defaultSettings();
    }
    try {
      return AppSettingsData.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>),
      );
    } catch (_) {
      return _defaultSettings();
    }
  }

  AppSettingsData _defaultSettings() {
    return const AppSettingsData(
      defaultGasUnit: AppSettingsDefaults.gasUnit,
      defaultGaugeType: AppSettingsDefaults.gaugeType,
      defaultBblPerInch: AppSettingsDefaults.bblPerInch,
      defaultGasCalculationMethod: AppSettingsDefaults.gasCalculationMethod,
      defaultChokeDisplay: AppSettingsDefaults.chokeDisplay,
      defaultOptionalReportSections: AppSettingsDefaults.optionalReportSections,
    );
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
