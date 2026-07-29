import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'drillout_cleanout_field_definitions.dart';
import 'operations_log_service.dart';

class OperationsLogFieldOption {
  const OperationsLogFieldOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class OperationsLogFieldConfig {
  const OperationsLogFieldConfig({
    required this.enabledFieldIds,
  });

  final Set<String> enabledFieldIds;

  bool isEnabled(String fieldId) => enabledFieldIds.contains(fieldId);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabledFieldIds': enabledFieldIds.toList(growable: false),
      };

  factory OperationsLogFieldConfig.fromJson(Map<String, dynamic> json) {
    final raw = (json['enabledFieldIds'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return OperationsLogFieldConfig(enabledFieldIds: raw);
  }
}

class OperationsLogFieldConfigService {
  static const String _prefsBase = 'wellwerks_operations_log_fields_v1';
  static const String _legacyShiftChangeBase =
      'wellwerks_drillout_shift_change_v1';

  static List<OperationsLogFieldOption> get configurableFields {
    return DrilloutCleanoutFieldDefinitions.readingFields
        .where(
          (field) =>
              field.id != DrilloutCleanoutFieldDefinitions.sweepInformationId,
        )
        .map(
          (field) => OperationsLogFieldOption(id: field.id, label: field.label),
        )
        .toList(growable: false);
  }

  static Set<String> get _defaultEnabled =>
      DrilloutCleanoutFieldDefinitions.defaultEnabledFieldIds;

  String _prefsKey({
    required OperationsLogWorkflow workflow,
    required String jobId,
  }) {
    final normalizedJobId = jobId.trim().isEmpty ? 'none' : jobId.trim();
    return '$_prefsBase:${workflow.name}:$normalizedJobId';
  }

  String _legacyKey(String jobId) {
    final normalizedJobId = jobId.trim();
    if (normalizedJobId.isEmpty) return _legacyShiftChangeBase;
    return '$_legacyShiftChangeBase:$normalizedJobId';
  }

  Future<OperationsLogFieldConfig> load({
    required OperationsLogWorkflow workflow,
    required String jobId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(workflow: workflow, jobId: jobId));
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = OperationsLogFieldConfig.fromJson(decoded);
        return _normalize(parsed);
      } catch (_) {
        // Fallback below.
      }
    }

    final migrated = await _fromLegacyShiftChange(
      workflow: workflow,
      jobId: jobId,
    );
    return _normalize(migrated);
  }

  Future<void> save({
    required OperationsLogWorkflow workflow,
    required String jobId,
    required OperationsLogFieldConfig config,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalize(config);
    await prefs.setString(
      _prefsKey(workflow: workflow, jobId: jobId),
      jsonEncode(normalized.toJson()),
    );
  }

  OperationsLogFieldConfig _normalize(OperationsLogFieldConfig config) {
    final allowed = configurableFields.map((item) => item.id).toSet()
      ..add(DrilloutCleanoutFieldDefinitions.sweepInformationId);
    final filtered = config.enabledFieldIds.where(allowed.contains).toSet();
    if (filtered.isEmpty) {
      return OperationsLogFieldConfig(enabledFieldIds: _defaultEnabled);
    }
    return OperationsLogFieldConfig(enabledFieldIds: filtered);
  }

  Future<OperationsLogFieldConfig> _fromLegacyShiftChange({
    required OperationsLogWorkflow workflow,
    required String jobId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey(jobId));
    if (raw == null || raw.trim().isEmpty) {
      return OperationsLogFieldConfig(enabledFieldIds: _defaultEnabled);
    }

    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final enabled = <String>{..._defaultEnabled};
      if ((map['includeRateOverride'] as bool?) ?? false) {
        enabled.add('pumpRate');
      }
      if ((map['includeCasingPsi'] as bool?) ?? false) {
        enabled.add('casingPressure');
      }
      if ((map['includePumpPsi'] as bool?) ?? false) {
        enabled.add('pumpPressure');
      }
      if ((map['includeManifoldPsi'] as bool?) ?? false) {
        enabled.add('tubingPressure');
      }
      if ((map['showStatus'] as bool?) ?? false) {
        enabled.add(DrilloutCleanoutFieldDefinitions.operationStageId);
      }
      if (((map['showGas'] as bool?) ?? false) ||
          ((map['showGasSpotRate'] as bool?) ?? false)) {
        enabled.add(DrilloutCleanoutFieldDefinitions.gasId);
      }
      if ((map['showSand'] as bool?) ?? false) {
        enabled.add(DrilloutCleanoutFieldDefinitions.sandOrSolidsId);
      }
      if ((map['showPlugNumber'] as bool?) ?? false) {
        enabled.add(DrilloutCleanoutFieldDefinitions.plugNumberId);
      }
      if ((map['includeSurfaceTotalFluid'] as bool?) ?? false) {
        enabled.add(DrilloutCleanoutFieldDefinitions.surfaceTotalFluidId);
      }
      if ((map['includeWaterHauled'] as bool?) ?? false) {
        enabled.add(DrilloutCleanoutFieldDefinitions.waterHauledId);
      }
      if ((map['includeOilHauled'] as bool?) ?? false) {
        enabled.add(DrilloutCleanoutFieldDefinitions.oilHauledId);
      }
      if ((map['showCoilDepth'] as bool?) ?? false) {
        enabled.add(DrilloutCleanoutFieldDefinitions.sweepInformationId);
      }
      if ((map['notes'] as String? ?? '').trim().isNotEmpty) {
        enabled.add(DrilloutCleanoutFieldDefinitions.notesId);
      }
      return OperationsLogFieldConfig(enabledFieldIds: enabled);
    } catch (_) {
      return OperationsLogFieldConfig(enabledFieldIds: _defaultEnabled);
    }
  }
}
