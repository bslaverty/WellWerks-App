import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  static const List<OperationsLogFieldOption> configurableFields =
      <OperationsLogFieldOption>[
    OperationsLogFieldOption(id: 'operationStage', label: 'Stage'),
    OperationsLogFieldOption(id: 'pumpRate', label: 'Rate Override'),
    OperationsLogFieldOption(id: 'casingPressure', label: 'Casing PSI'),
    OperationsLogFieldOption(id: 'pumpPressure', label: 'Pump PSI'),
    OperationsLogFieldOption(id: 'tubingPressure', label: 'Manifold PSI'),
    OperationsLogFieldOption(id: 'returnsRate', label: 'Returns Rate'),
    OperationsLogFieldOption(id: 'waterRate', label: 'Water Rate'),
    OperationsLogFieldOption(id: 'flowRate', label: 'Flow Rate'),
    OperationsLogFieldOption(id: 'tankLevel', label: 'Tank Level'),
    OperationsLogFieldOption(id: 'choke', label: 'Choke'),
    OperationsLogFieldOption(
        id: 'sweepInformation', label: 'Sweep Information'),
    OperationsLogFieldOption(id: 'sandOrSolids', label: 'Sand / Solids'),
    OperationsLogFieldOption(id: 'equipmentStatus', label: 'Equipment Issues'),
    OperationsLogFieldOption(id: 'downtime', label: 'Downtime'),
    OperationsLogFieldOption(id: 'notes', label: 'Notes'),
  ];

  static const Set<String> _defaultEnabled = <String>{
    'operationStage',
    'pumpRate',
    'casingPressure',
    'pumpPressure',
    'notes',
  };

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
    final allowed = configurableFields.map((item) => item.id).toSet();
    final filtered = config.enabledFieldIds.where(allowed.contains).toSet();
    if (filtered.isEmpty) {
      return const OperationsLogFieldConfig(enabledFieldIds: _defaultEnabled);
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
      return const OperationsLogFieldConfig(enabledFieldIds: _defaultEnabled);
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
        enabled.add('operationStage');
      }
      if ((map['showSand'] as bool?) ?? false) {
        enabled.add('sandOrSolids');
      }
      if ((map['showCoilDepth'] as bool?) ?? false) {
        enabled.add('sweepInformation');
      }
      if ((map['notes'] as String? ?? '').trim().isNotEmpty) {
        enabled.add('notes');
      }
      if (workflow == OperationsLogWorkflow.cleanout) {
        enabled.add('waterRate');
      }
      return OperationsLogFieldConfig(enabledFieldIds: enabled);
    } catch (_) {
      return const OperationsLogFieldConfig(enabledFieldIds: _defaultEnabled);
    }
  }
}
