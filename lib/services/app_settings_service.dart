import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/job_history_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/production_shift_service.dart';

class AppSettingsDefaults {
  static const gasUnit = 'mcfd';
  static const gaugeType = 'inches';
  static const bblPerInch = '1.67';
  static const gasCalculationMethod = 'accumulator';
  static const chokeDisplay = 'ADJ';
  static const productionActiveJobDefaults = true;
  static const productionReportLayout = 'standard';
  static const productionTextUpdateLayout = 'standard';
  static const completionsRateDisplayDefault = 'bbl_min';
  static const completionsTimerDefaultMinutes = 10;
  static const jsaAutoDate = true;
  static const jsaAutoTime = true;
  static const jsaAutoLocation = false;
  static const jsaAutoWeather = false;
  static const jsaCompanyDefault = 'Mach Energy';
  static const layoutInventoryMode = 'standard';
  static const layoutDefaultEquipment = 'flowback';
  static const chartsChloridesDefault = 'ppm';
  static const chartsUnits = 'field';
  static const historyRetentionDays = 30;
  static const historyExportMode = 'csv';
  static const appNotifications = true;
  static const textTimeFormat = '12h';
  static const rateTimerNotificationsEnabled = true;
  static const rateTimerWarningEnabled = true;
  static const rateTimerCompleteEnabled = true;
  static const rateTimerSoundEnabled = true;
  static const estimatedStsReminderEnabled = true;
  static const estimatedStsReminderLeadMinutes = 10;
  static const autoSaveRateCalculationsToOperationsLog = true;
  static const appTheme = 'wellwerks_default';
  static const activeCompany = JobProfileDefaultsService.companyNone;
  static const optionalReportSections = [
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
    this.productionActiveJobDefaults =
        AppSettingsDefaults.productionActiveJobDefaults,
    this.productionReportLayout = AppSettingsDefaults.productionReportLayout,
    this.productionTextUpdateLayout =
        AppSettingsDefaults.productionTextUpdateLayout,
    this.completionsRateDisplayDefault =
        AppSettingsDefaults.completionsRateDisplayDefault,
    this.completionsTimerDefaultMinutes =
        AppSettingsDefaults.completionsTimerDefaultMinutes,
    this.jsaAutoDate = AppSettingsDefaults.jsaAutoDate,
    this.jsaAutoTime = AppSettingsDefaults.jsaAutoTime,
    this.jsaAutoLocation = AppSettingsDefaults.jsaAutoLocation,
    this.jsaAutoWeather = AppSettingsDefaults.jsaAutoWeather,
    this.jsaCompanyDefault = AppSettingsDefaults.jsaCompanyDefault,
    this.layoutInventoryMode = AppSettingsDefaults.layoutInventoryMode,
    this.layoutDefaultEquipment = AppSettingsDefaults.layoutDefaultEquipment,
    this.chartsChloridesDefault = AppSettingsDefaults.chartsChloridesDefault,
    this.chartsUnits = AppSettingsDefaults.chartsUnits,
    this.historyRetentionDays = AppSettingsDefaults.historyRetentionDays,
    this.historyExportMode = AppSettingsDefaults.historyExportMode,
    this.appNotifications = AppSettingsDefaults.appNotifications,
    this.textTimeFormat = AppSettingsDefaults.textTimeFormat,
    this.rateTimerNotificationsEnabled =
        AppSettingsDefaults.rateTimerNotificationsEnabled,
    this.rateTimerWarningEnabled = AppSettingsDefaults.rateTimerWarningEnabled,
    this.rateTimerCompleteEnabled =
        AppSettingsDefaults.rateTimerCompleteEnabled,
    this.rateTimerSoundEnabled = AppSettingsDefaults.rateTimerSoundEnabled,
    this.estimatedStsReminderEnabled =
        AppSettingsDefaults.estimatedStsReminderEnabled,
    this.estimatedStsReminderLeadMinutes =
        AppSettingsDefaults.estimatedStsReminderLeadMinutes,
    this.autoSaveRateCalculationsToOperationsLog =
        AppSettingsDefaults.autoSaveRateCalculationsToOperationsLog,
    this.appTheme = AppSettingsDefaults.appTheme,
    this.activeCompany = AppSettingsDefaults.activeCompany,
  });

  final String defaultGasUnit;
  final String defaultGaugeType;
  final String defaultBblPerInch;
  final String defaultGasCalculationMethod;
  final String defaultChokeDisplay;
  final List<String> defaultOptionalReportSections;
  final bool productionActiveJobDefaults;
  final String productionReportLayout;
  final String productionTextUpdateLayout;
  final String completionsRateDisplayDefault;
  final int completionsTimerDefaultMinutes;
  final bool jsaAutoDate;
  final bool jsaAutoTime;
  final bool jsaAutoLocation;
  final bool jsaAutoWeather;
  final String jsaCompanyDefault;
  final String layoutInventoryMode;
  final String layoutDefaultEquipment;
  final String chartsChloridesDefault;
  final String chartsUnits;
  final int historyRetentionDays;
  final String historyExportMode;
  final bool appNotifications;
  final String textTimeFormat;
  final bool rateTimerNotificationsEnabled;
  final bool rateTimerWarningEnabled;
  final bool rateTimerCompleteEnabled;
  final bool rateTimerSoundEnabled;
  final bool estimatedStsReminderEnabled;
  final int estimatedStsReminderLeadMinutes;
  final bool autoSaveRateCalculationsToOperationsLog;
  final String appTheme;
  final String activeCompany;

  static const optionalReportSectionOptions = [
    AppOptionalReportSection(id: 'vru', label: 'VRU'),
    AppOptionalReportSection(id: 'flare', label: 'Flare'),
    AppOptionalReportSection(id: 'ecd', label: 'ECD'),
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
    bool? productionActiveJobDefaults,
    String? productionReportLayout,
    String? productionTextUpdateLayout,
    String? completionsRateDisplayDefault,
    int? completionsTimerDefaultMinutes,
    bool? jsaAutoDate,
    bool? jsaAutoTime,
    bool? jsaAutoLocation,
    bool? jsaAutoWeather,
    String? jsaCompanyDefault,
    String? layoutInventoryMode,
    String? layoutDefaultEquipment,
    String? chartsChloridesDefault,
    String? chartsUnits,
    int? historyRetentionDays,
    String? historyExportMode,
    bool? appNotifications,
    String? textTimeFormat,
    bool? rateTimerNotificationsEnabled,
    bool? rateTimerWarningEnabled,
    bool? rateTimerCompleteEnabled,
    bool? rateTimerSoundEnabled,
    bool? estimatedStsReminderEnabled,
    int? estimatedStsReminderLeadMinutes,
    bool? autoSaveRateCalculationsToOperationsLog,
    String? appTheme,
    String? activeCompany,
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
      productionActiveJobDefaults:
          productionActiveJobDefaults ?? this.productionActiveJobDefaults,
      productionReportLayout:
          productionReportLayout ?? this.productionReportLayout,
      productionTextUpdateLayout:
          productionTextUpdateLayout ?? this.productionTextUpdateLayout,
      completionsRateDisplayDefault:
          completionsRateDisplayDefault ?? this.completionsRateDisplayDefault,
      completionsTimerDefaultMinutes:
          completionsTimerDefaultMinutes ?? this.completionsTimerDefaultMinutes,
      jsaAutoDate: jsaAutoDate ?? this.jsaAutoDate,
      jsaAutoTime: jsaAutoTime ?? this.jsaAutoTime,
      jsaAutoLocation: jsaAutoLocation ?? this.jsaAutoLocation,
      jsaAutoWeather: jsaAutoWeather ?? this.jsaAutoWeather,
      jsaCompanyDefault: jsaCompanyDefault ?? this.jsaCompanyDefault,
      layoutInventoryMode: layoutInventoryMode ?? this.layoutInventoryMode,
      layoutDefaultEquipment:
          layoutDefaultEquipment ?? this.layoutDefaultEquipment,
      chartsChloridesDefault:
          chartsChloridesDefault ?? this.chartsChloridesDefault,
      chartsUnits: chartsUnits ?? this.chartsUnits,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
      historyExportMode: historyExportMode ?? this.historyExportMode,
      appNotifications: appNotifications ?? this.appNotifications,
      textTimeFormat: textTimeFormat ?? this.textTimeFormat,
      rateTimerNotificationsEnabled:
          rateTimerNotificationsEnabled ?? this.rateTimerNotificationsEnabled,
      rateTimerWarningEnabled:
          rateTimerWarningEnabled ?? this.rateTimerWarningEnabled,
      rateTimerCompleteEnabled:
          rateTimerCompleteEnabled ?? this.rateTimerCompleteEnabled,
      rateTimerSoundEnabled:
          rateTimerSoundEnabled ?? this.rateTimerSoundEnabled,
      estimatedStsReminderEnabled:
          estimatedStsReminderEnabled ?? this.estimatedStsReminderEnabled,
      estimatedStsReminderLeadMinutes: estimatedStsReminderLeadMinutes ??
          this.estimatedStsReminderLeadMinutes,
      autoSaveRateCalculationsToOperationsLog:
          autoSaveRateCalculationsToOperationsLog ??
              this.autoSaveRateCalculationsToOperationsLog,
      appTheme: appTheme ?? this.appTheme,
      activeCompany: activeCompany ?? this.activeCompany,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultGasUnit': defaultGasUnit,
        'defaultGaugeType': defaultGaugeType,
        'defaultBblPerInch': defaultBblPerInch,
        'defaultGasCalculationMethod': defaultGasCalculationMethod,
        'defaultChokeDisplay': defaultChokeDisplay,
        'defaultOptionalReportSections': defaultOptionalReportSections,
        'productionActiveJobDefaults': productionActiveJobDefaults,
        'productionReportLayout': productionReportLayout,
        'productionTextUpdateLayout': productionTextUpdateLayout,
        'completionsRateDisplayDefault': completionsRateDisplayDefault,
        'completionsTimerDefaultMinutes': completionsTimerDefaultMinutes,
        'jsaAutoDate': jsaAutoDate,
        'jsaAutoTime': jsaAutoTime,
        'jsaAutoLocation': jsaAutoLocation,
        'jsaAutoWeather': jsaAutoWeather,
        'jsaCompanyDefault': jsaCompanyDefault,
        'layoutInventoryMode': layoutInventoryMode,
        'layoutDefaultEquipment': layoutDefaultEquipment,
        'chartsChloridesDefault': chartsChloridesDefault,
        'chartsUnits': chartsUnits,
        'historyRetentionDays': historyRetentionDays,
        'historyExportMode': historyExportMode,
        'appNotifications': appNotifications,
        'textTimeFormat': textTimeFormat,
        'rateTimerNotificationsEnabled': rateTimerNotificationsEnabled,
        'rateTimerWarningEnabled': rateTimerWarningEnabled,
        'rateTimerCompleteEnabled': rateTimerCompleteEnabled,
        'rateTimerSoundEnabled': rateTimerSoundEnabled,
        'estimatedStsReminderEnabled': estimatedStsReminderEnabled,
        'estimatedStsReminderLeadMinutes': estimatedStsReminderLeadMinutes,
        'autoSaveRateCalculationsToOperationsLog':
            autoSaveRateCalculationsToOperationsLog,
        'appTheme': appTheme,
        'activeCompany': activeCompany,
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
      productionActiveJobDefaults:
          json['productionActiveJobDefaults'] as bool? ??
              AppSettingsDefaults.productionActiveJobDefaults,
      productionReportLayout:
          _normalizeProductionReportLayout(json['productionReportLayout']),
      productionTextUpdateLayout: _normalizeTextUpdateLayout(
        json['productionTextUpdateLayout'],
      ),
      completionsRateDisplayDefault: _normalizeRateDisplayDefault(
        json['completionsRateDisplayDefault'],
      ),
      completionsTimerDefaultMinutes: _normalizeTimerDefaultMinutes(
        json['completionsTimerDefaultMinutes'],
      ),
      jsaAutoDate:
          json['jsaAutoDate'] as bool? ?? AppSettingsDefaults.jsaAutoDate,
      jsaAutoTime:
          json['jsaAutoTime'] as bool? ?? AppSettingsDefaults.jsaAutoTime,
      jsaAutoLocation: json['jsaAutoLocation'] as bool? ??
          AppSettingsDefaults.jsaAutoLocation,
      jsaAutoWeather:
          json['jsaAutoWeather'] as bool? ?? AppSettingsDefaults.jsaAutoWeather,
      jsaCompanyDefault:
          _normalizeCompanyDefault(json['jsaCompanyDefault'] as String?),
      layoutInventoryMode:
          _normalizeLayoutInventoryMode(json['layoutInventoryMode'] as String?),
      layoutDefaultEquipment: _normalizeDefaultEquipment(
        json['layoutDefaultEquipment'] as String?,
      ),
      chartsChloridesDefault: _normalizeChloridesDefault(
        json['chartsChloridesDefault'] as String?,
      ),
      chartsUnits: _normalizeChartsUnits(json['chartsUnits'] as String?),
      historyRetentionDays: _normalizeHistoryRetentionDays(
        json['historyRetentionDays'],
      ),
      historyExportMode:
          _normalizeHistoryExportMode(json['historyExportMode'] as String?),
      appNotifications: json['appNotifications'] as bool? ??
          AppSettingsDefaults.appNotifications,
      textTimeFormat: _normalizeTextTimeFormat(
        json['textTimeFormat'] as String?,
      ),
      rateTimerNotificationsEnabled:
          json['rateTimerNotificationsEnabled'] as bool? ??
              AppSettingsDefaults.rateTimerNotificationsEnabled,
      rateTimerWarningEnabled: json['rateTimerWarningEnabled'] as bool? ??
          AppSettingsDefaults.rateTimerWarningEnabled,
      rateTimerCompleteEnabled: json['rateTimerCompleteEnabled'] as bool? ??
          AppSettingsDefaults.rateTimerCompleteEnabled,
      rateTimerSoundEnabled: json['rateTimerSoundEnabled'] as bool? ??
          AppSettingsDefaults.rateTimerSoundEnabled,
      estimatedStsReminderEnabled:
          json['estimatedStsReminderEnabled'] as bool? ??
              AppSettingsDefaults.estimatedStsReminderEnabled,
      estimatedStsReminderLeadMinutes:
          _normalizeEstimatedStsReminderLeadMinutes(
        json['estimatedStsReminderLeadMinutes'],
      ),
      autoSaveRateCalculationsToOperationsLog:
          json['autoSaveRateCalculationsToOperationsLog'] as bool? ??
              AppSettingsDefaults.autoSaveRateCalculationsToOperationsLog,
      appTheme: _normalizeTheme(json['appTheme'] as String?),
      activeCompany: _normalizeActiveCompany(json['activeCompany'] as String?),
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

  static String _normalizeProductionReportLayout(dynamic value) {
    final normalized = (value?.toString() ?? '').trim().toLowerCase();
    return normalized == 'detailed' ? 'detailed' : 'standard';
  }

  static String _normalizeTextUpdateLayout(dynamic value) {
    final normalized = (value?.toString() ?? '').trim().toLowerCase();
    return normalized == 'compact' ? 'compact' : 'standard';
  }

  static String _normalizeRateDisplayDefault(dynamic value) {
    final normalized = (value?.toString() ?? '').trim().toLowerCase();
    return normalized == 'bbl_hr' ? 'bbl_hr' : 'bbl_min';
  }

  static int _normalizeTimerDefaultMinutes(dynamic value) {
    final parsed = (value is num)
        ? value.toInt()
        : int.tryParse((value ?? '').toString().trim());
    if (parsed == null || parsed < 1 || parsed > 60) {
      return AppSettingsDefaults.completionsTimerDefaultMinutes;
    }
    return parsed;
  }

  static String _normalizeCompanyDefault(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? AppSettingsDefaults.jsaCompanyDefault : trimmed;
  }

  static String _normalizeLayoutInventoryMode(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'compact' ? 'compact' : 'standard';
  }

  static String _normalizeDefaultEquipment(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'full' ? 'full' : 'flowback';
  }

  static String _normalizeChloridesDefault(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'mg_l' ? 'mg_l' : 'ppm';
  }

  static String _normalizeChartsUnits(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'metric' ? 'metric' : 'field';
  }

  static int _normalizeHistoryRetentionDays(dynamic value) {
    final parsed = (value is num)
        ? value.toInt()
        : int.tryParse((value ?? '').toString().trim());
    if (parsed == null || parsed < 7 || parsed > 3650) {
      return AppSettingsDefaults.historyRetentionDays;
    }
    return parsed;
  }

  static String _normalizeHistoryExportMode(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'json' ? 'json' : 'csv';
  }

  static String _normalizeTextTimeFormat(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == '24h' ? '24h' : '12h';
  }

  static String _normalizeTheme(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'negative':
      case 'patriot':
      case 'osu':
      case 'ou':
      case 'military':
      case 'light':
      case 'high_vis':
      case 'wellwerks_default':
        return normalized;
      case 'high_visibility':
        return 'light';
      case 'wellwerks_dark':
      case 'dark':
        return 'wellwerks_default';
      default:
        return AppSettingsDefaults.appTheme;
    }
  }

  static int _normalizeEstimatedStsReminderLeadMinutes(dynamic value) {
    final parsed = (value is num)
        ? value.toInt()
        : int.tryParse((value ?? '').toString().trim());
    switch (parsed) {
      case 5:
      case 10:
      case 15:
      case 20:
      case 30:
      case 45:
      case 60:
        return parsed!;
      default:
        return AppSettingsDefaults.estimatedStsReminderLeadMinutes;
    }
  }

  static String _normalizeActiveCompany(String? value) {
    final normalized =
        JobProfileDefaultsService().normalizeCompany((value ?? '').trim());
    if (normalized.trim().isEmpty) {
      return JobProfileDefaultsService.companyNone;
    }
    return normalized;
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
      productionActiveJobDefaults:
          AppSettingsDefaults.productionActiveJobDefaults,
      productionReportLayout: AppSettingsDefaults.productionReportLayout,
      productionTextUpdateLayout:
          AppSettingsDefaults.productionTextUpdateLayout,
      completionsRateDisplayDefault:
          AppSettingsDefaults.completionsRateDisplayDefault,
      completionsTimerDefaultMinutes:
          AppSettingsDefaults.completionsTimerDefaultMinutes,
      jsaAutoDate: AppSettingsDefaults.jsaAutoDate,
      jsaAutoTime: AppSettingsDefaults.jsaAutoTime,
      jsaAutoLocation: AppSettingsDefaults.jsaAutoLocation,
      jsaAutoWeather: AppSettingsDefaults.jsaAutoWeather,
      jsaCompanyDefault: AppSettingsDefaults.jsaCompanyDefault,
      layoutInventoryMode: AppSettingsDefaults.layoutInventoryMode,
      layoutDefaultEquipment: AppSettingsDefaults.layoutDefaultEquipment,
      chartsChloridesDefault: AppSettingsDefaults.chartsChloridesDefault,
      chartsUnits: AppSettingsDefaults.chartsUnits,
      historyRetentionDays: AppSettingsDefaults.historyRetentionDays,
      historyExportMode: AppSettingsDefaults.historyExportMode,
      appNotifications: AppSettingsDefaults.appNotifications,
      textTimeFormat: AppSettingsDefaults.textTimeFormat,
      rateTimerNotificationsEnabled:
          AppSettingsDefaults.rateTimerNotificationsEnabled,
      rateTimerWarningEnabled: AppSettingsDefaults.rateTimerWarningEnabled,
      rateTimerCompleteEnabled: AppSettingsDefaults.rateTimerCompleteEnabled,
      rateTimerSoundEnabled: AppSettingsDefaults.rateTimerSoundEnabled,
      estimatedStsReminderEnabled:
          AppSettingsDefaults.estimatedStsReminderEnabled,
      estimatedStsReminderLeadMinutes:
          AppSettingsDefaults.estimatedStsReminderLeadMinutes,
      autoSaveRateCalculationsToOperationsLog:
          AppSettingsDefaults.autoSaveRateCalculationsToOperationsLog,
      appTheme: AppSettingsDefaults.appTheme,
      activeCompany: AppSettingsDefaults.activeCompany,
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
