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

  static const List<ReportField> availableFields = [
    ReportField(key: 'time', label: 'Time'),
    ReportField(key: 'well', label: 'Well'),
    ReportField(key: 'csg', label: 'CSG'),
    ReportField(key: 'icp', label: 'ICP'),
    ReportField(key: 'chk', label: 'CHK'),
    ReportField(key: 'bwph', label: 'BWPH'),
    ReportField(key: 'boph', label: 'BOPH'),
    ReportField(key: 'gasSpotRt', label: 'GAS SPOT RT.'),
    ReportField(key: 'diff', label: 'DIFF'),
    ReportField(key: 'stat', label: 'STAT'),
    ReportField(key: 'temp', label: 'TEMP'),
    ReportField(key: 'prop', label: 'PROP'),
    ReportField(key: 'h2oSg', label: 'H2O SG'),
    ReportField(key: 'wht', label: 'WHT'),
    ReportField(key: 'wtrTmp', label: 'WTR TMP'),
    ReportField(key: 'flareRt', label: 'FLARE RT'),
    ReportField(key: 'flarePilotTemp', label: 'FLARE PILOT TEMP'),
    ReportField(key: 'biocide', label: 'BIOCIDE'),
    ReportField(key: 'vruGasRt', label: 'VRU GAS RT'),
    ReportField(key: 'compressorInj', label: 'COMP INJ'),
    ReportField(key: 'vruSuction', label: 'VRU SUCTION'),
    ReportField(key: 'vruDischarge', label: 'VRU DISCHARGE'),
    ReportField(key: 'notes', label: 'Notes'),
  ];

  ReportLayoutProfile defaultProfile() {
    return const ReportLayoutProfile(
      id: 'default',
      name: 'Default',
      reportFields: availableFields,
      textFields: availableFields,
    );
  }

  List<ReportField> _normalizeFields(List<ReportField> fields) {
    final byKey = {for (final field in fields) field.key: field};
    return availableFields.map((base) {
      final existing = byKey[base.key];
      if (existing == null) return base;
      return ReportField(
        key: base.key,
        label: base.label,
        required: existing.required,
        included: existing.included,
      );
    }).toList();
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
      parsed = [defaultProfile()];
    }

    if (!parsed.any((item) => item.id == 'default')) {
      parsed.insert(0, defaultProfile());
    }

    final normalized = parsed
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
    return prefs.getString(_activeProfileIdKey) ?? 'default';
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
