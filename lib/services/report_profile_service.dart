import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReportField {
  const ReportField({
    required this.key,
    required this.label,
    this.required = false,
    this.included = true,
  });

  final String key;
  final String label;
  final bool required;
  final bool included;

  ReportField copyWith({
    String? key,
    String? label,
    bool? required,
    bool? included,
  }) {
    return ReportField(
      key: key ?? this.key,
      label: label ?? this.label,
      required: required ?? this.required,
      included: included ?? this.included,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'required': required,
        'included': included,
      };

  factory ReportField.fromJson(Map<String, dynamic> json) => ReportField(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        required: json['required'] as bool? ?? false,
        included: json['included'] as bool? ?? true,
      );
}

class ReportLayoutProfile {
  const ReportLayoutProfile({
    required this.id,
    required this.name,
    required this.reportFields,
    required this.textFields,
  });

  final String id;
  final String name;
  final List<ReportField> reportFields;
  final List<ReportField> textFields;

  ReportLayoutProfile copyWith({
    String? id,
    String? name,
    List<ReportField>? reportFields,
    List<ReportField>? textFields,
  }) {
    return ReportLayoutProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      reportFields: reportFields ?? this.reportFields,
      textFields: textFields ?? this.textFields,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'reportFields': reportFields.map((f) => f.toJson()).toList(),
        'textFields': textFields.map((f) => f.toJson()).toList(),
      };

  factory ReportLayoutProfile.fromJson(Map<String, dynamic> json) =>
      ReportLayoutProfile(
        id: json['id'] as String? ?? 'default',
        name: json['name'] as String? ?? 'Default',
        reportFields: (json['reportFields'] as List? ?? const [])
            .map((item) => ReportField.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        textFields: (json['textFields'] as List? ?? const [])
            .map((item) => ReportField.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );
}

class ReportProfileService {
  static const String _profilesKey = 'wellwerks_report_layout_profiles_v2';
  static const String _activeProfileIdKey =
      'wellwerks_report_layout_active_profile_v2';

  static const String defaultProfileId = 'default';
  static const String continentalProfileId = 'continental_resources';
  static const String machProfileId = 'mach_energy';
  static const String flywheelProfileId = 'flywheel_energy';
  static const String customProfileId = 'custom';

  static const List<ReportField> availableFields = [
    ReportField(key: 'time', label: 'Time'),
    ReportField(key: 'well', label: 'Well'),
    ReportField(key: 'wellName', label: 'Well Name'),
    ReportField(key: 'tbg', label: 'Tubing'),
    ReportField(key: 'csg', label: 'CSG'),
    ReportField(key: 'icp', label: 'ICP'),
    ReportField(key: 'chk', label: 'CHK'),
    ReportField(key: 'bwph', label: 'BWPH'),
    ReportField(key: 'boph', label: 'BOPH'),
    ReportField(key: 'gasSpotRt', label: 'GAS RATE'),
    ReportField(key: 'diff', label: 'DIFF'),
    ReportField(key: 'stat', label: 'STAT'),
    ReportField(key: 'temp', label: 'TEMP'),
    ReportField(key: 'prop', label: 'PROP'),
    ReportField(key: 'h2oSg', label: 'H2O SG'),
    ReportField(key: 'wht', label: 'WHT'),
    ReportField(key: 'wtrTmp', label: 'WTR TMP'),
    ReportField(key: 'flareRt', label: 'FLARE RT'),
    ReportField(key: 'flarePilotTemp', label: 'FLARE PILOT TEMP'),
    ReportField(key: 'flareEcdTemp', label: 'FLARE / ECD TEMP'),
    ReportField(key: 'flareEcdGasRate', label: 'FLARE / ECD GAS RATE'),
    ReportField(key: 'biocide', label: 'BIOCIDE'),
    ReportField(key: 'scavenger', label: 'SCAVENGER'),
    ReportField(key: 'defoamer', label: 'DEFOAMER'),
    ReportField(key: 'scaleInhibitor', label: 'SCALE INHIBITOR'),
    ReportField(key: 'vruGasRt', label: 'VRU GAS RT'),
    ReportField(key: 'vruSuct', label: 'VRU SUCT'),
    ReportField(key: 'vruDisc', label: 'VRU DISC'),
    ReportField(key: 'compressorInj', label: 'COMP INJ'),
    ReportField(key: 'vruSuction', label: 'VRU SUCTION'),
    ReportField(key: 'vruDischarge', label: 'VRU DISCHARGE'),
    ReportField(key: 'notes', label: 'Notes'),
  ];

  static const List<String> _continentalPresetKeys = [
    'csg',
    'icp',
    'chk',
    'bwph',
    'boph',
    'gasSpotRt',
    'stat',
    'diff',
    'temp',
    'prop',
    'wht',
    'biocide',
    'scavenger',
    'defoamer',
    'scaleInhibitor',
    'flareEcdTemp',
    'flareEcdGasRate',
    'vruGasRt',
    'vruSuct',
    'vruDisc',
    'notes',
  ];

  static const Map<String, String> _continentalLabels = {
    'csg': 'CSG',
    'icp': 'ICP',
    'chk': 'CHK',
    'bwph': 'H2O',
    'boph': 'OIL',
    'gasSpotRt': 'GAS RATE',
    'stat': 'STAT',
    'diff': 'DIFF',
    'temp': 'TEMP',
    'prop': 'SAND',
    'wht': 'WHT',
    'biocide': 'BIO',
    'scavenger': 'SCAV',
    'defoamer': 'DEF',
    'scaleInhibitor': 'SCALE INH',
    'flareEcdTemp': 'FLARE / ECD TEMP',
    'flareEcdGasRate': 'FLARE / ECD GAS RATE',
    'vruGasRt': 'VRU GAS RT',
    'vruSuct': 'VRU SUCT',
    'vruDisc': 'VRU DISC',
    'notes': 'Notes',
  };

  static const List<String> _machPresetKeys = [
    'wellName',
    'chk',
    'csg',
    'bwph',
    'boph',
    'gasSpotRt',
    'prop',
    'notes',
  ];

  static const Map<String, String> _machLabels = {
    'wellName': 'Well Name',
    'chk': 'Choke',
    'csg': 'Csg',
    'bwph': 'Wtr/hr',
    'boph': 'Oil',
    'gasSpotRt': 'Gas Rate',
    'prop': 'Sand',
    'notes': 'Notes',
  };

  static const List<String> _flywheelPresetKeys = [
    'tbg',
    'csg',
    'chk',
    'boph',
    'bwph',
    'diff',
    'stat',
    'temp',
    'gasSpotRt',
    'prop',
  ];

  static const Map<String, String> _flywheelLabels = {
    'tbg': 'Tubing',
    'csg': 'CSG',
    'chk': 'Ck',
    'boph': 'Oil',
    'bwph': 'Wtr',
    'diff': 'Diff',
    'stat': 'Stat',
    'temp': 'Temp',
    'gasSpotRt': 'GAS RATE',
    'prop': 'Sand',
  };

  ReportLayoutProfile defaultProfile() {
    return const ReportLayoutProfile(
      id: defaultProfileId,
      name: 'Default',
      reportFields: availableFields,
      textFields: availableFields,
    );
  }

  ReportLayoutProfile continentalProfile() {
    final fields = _presetFields(
      keys: _continentalPresetKeys,
      labels: _continentalLabels,
    );
    return ReportLayoutProfile(
      id: continentalProfileId,
      name: 'Continental Resources',
      reportFields: fields,
      textFields: fields,
    );
  }

  ReportLayoutProfile machProfile() {
    final fields = _presetFields(keys: _machPresetKeys, labels: _machLabels);
    return ReportLayoutProfile(
      id: machProfileId,
      name: 'Mach Energy',
      reportFields: fields,
      textFields: fields,
    );
  }

  ReportLayoutProfile flywheelProfile() {
    final fields =
        _presetFields(keys: _flywheelPresetKeys, labels: _flywheelLabels);
    return ReportLayoutProfile(
      id: flywheelProfileId,
      name: 'Flywheel Energy',
      reportFields: fields,
      textFields: fields,
    );
  }

  ReportLayoutProfile customProfile() {
    return ReportLayoutProfile(
      id: customProfileId,
      name: 'Custom',
      reportFields: List<ReportField>.from(availableFields),
      textFields: List<ReportField>.from(availableFields),
    );
  }

  List<ReportLayoutProfile> systemProfiles() {
    return [
      defaultProfile(),
      continentalProfile(),
      machProfile(),
      flywheelProfile(),
      customProfile(),
    ];
  }

  bool isSystemProfileId(String id) {
    return id == defaultProfileId ||
        id == continentalProfileId ||
        id == machProfileId ||
        id == flywheelProfileId ||
        id == customProfileId;
  }

  List<ReportField> _presetFields({
    required List<String> keys,
    required Map<String, String> labels,
  }) {
    final byKey = {for (final field in availableFields) field.key: field};
    final fields = <ReportField>[];
    for (final key in keys) {
      final base = byKey[key];
      if (base == null) continue;
      fields.add(ReportField(
        key: key,
        label: labels[key] ?? base.label,
      ));
    }
    return fields;
  }

  List<ReportField> _normalizeFields(List<ReportField> fields) {
    final baseByKey = {for (final field in availableFields) field.key: field};
    final normalized = <ReportField>[];
    final seen = <String>{};

    for (final field in fields) {
      final base = baseByKey[field.key];
      if (base == null || seen.contains(field.key)) continue;
      seen.add(field.key);
      normalized.add(ReportField(
        key: field.key,
        label: field.label.trim().isEmpty ? base.label : field.label,
        required: field.required,
        included: field.included,
      ));
    }

    if (normalized.isNotEmpty) {
      return normalized;
    }

    return List<ReportField>.from(availableFields);
  }

  Future<List<ReportLayoutProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    List<ReportLayoutProfile> parsed;

    if (raw == null || raw.isEmpty) {
      parsed = [defaultProfile()];
    } else {
      try {
        parsed = (jsonDecode(raw) as List<dynamic>)
            .map((item) => ReportLayoutProfile.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList();
      } catch (_) {
        parsed = [defaultProfile()];
      }
    }

    if (parsed.isEmpty) {
      parsed = systemProfiles();
    }

    final parsedById = {for (final profile in parsed) profile.id: profile};
    final merged = <ReportLayoutProfile>[];

    for (final preset in systemProfiles()) {
      merged.add(parsedById[preset.id] ?? preset);
    }

    for (final profile in parsed) {
      if (!isSystemProfileId(profile.id)) {
        merged.add(profile);
      }
    }

    final normalized = merged
        .map((profile) => profile.copyWith(
              reportFields: _normalizeFields(profile.reportFields),
              textFields: _normalizeFields(profile.textFields),
            ))
        .toList();

    await saveProfiles(normalized);
    return normalized;
  }

  Future<void> saveProfiles(List<ReportLayoutProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
  }

  Future<String> loadActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProfileIdKey) ?? defaultProfileId;
  }

  Future<void> setActiveProfileId(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileIdKey, profileId);
  }

  Future<ReportLayoutProfile> loadActiveProfile() async {
    final profiles = await loadProfiles();
    final activeId = await loadActiveProfileId();
    return profiles.firstWhere(
      (item) => item.id == activeId,
      orElse: () => profiles.first,
    );
  }

  Future<ReportLayoutProfile> resolveProfile(String? requestedId) async {
    final profiles = await loadProfiles();
    if (requestedId != null && requestedId.trim().isNotEmpty) {
      final requested =
          profiles.where((item) => item.id == requestedId).toList();
      if (requested.isNotEmpty) {
        return requested.first;
      }
    }
    final activeId = await loadActiveProfileId();
    return profiles.firstWhere(
      (item) => item.id == activeId,
      orElse: () => profiles.first,
    );
  }

  Future<List<ReportLayoutProfile>> createProfile({
    required String name,
    ReportLayoutProfile? source,
  }) async {
    final profiles = await loadProfiles();
    final template = source ?? profiles.first;
    final nowId = DateTime.now().microsecondsSinceEpoch.toString();
    final created = template.copyWith(
      id: nowId,
      name: name.trim().isEmpty ? 'Untitled Layout' : name.trim(),
    );
    final next = [...profiles, created];
    await saveProfiles(next);
    return next;
  }

  Future<List<ReportLayoutProfile>> upsertProfile(
      ReportLayoutProfile profile) async {
    final profiles = await loadProfiles();
    final next = profiles.map((item) {
      if (item.id != profile.id) return item;
      return profile.copyWith(
        reportFields: _normalizeFields(profile.reportFields),
        textFields: _normalizeFields(profile.textFields),
      );
    }).toList();
    await saveProfiles(next);
    return next;
  }

  Future<List<ReportLayoutProfile>> deleteProfile(String id) async {
    if (isSystemProfileId(id)) {
      return loadProfiles();
    }
    var profiles = await loadProfiles();
    if (profiles.length <= 1) return profiles;
    profiles = profiles.where((item) => item.id != id).toList();
    if (profiles.isEmpty) {
      profiles = [defaultProfile()];
    }
    await saveProfiles(profiles);

    final activeId = await loadActiveProfileId();
    if (!profiles.any((item) => item.id == activeId)) {
      await setActiveProfileId(profiles.first.id);
    }
    return profiles;
  }
}
