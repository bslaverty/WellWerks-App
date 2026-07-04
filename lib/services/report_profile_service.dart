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

  ReportField copyWith({bool? required, bool? included}) => ReportField(
        key: key,
        label: label,
        required: required ?? this.required,
        included: included ?? this.included,
      );

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

class ReportProfile {
  const ReportProfile({required this.name, required this.fields});

  final String name;
  final List<ReportField> fields;

  Map<String, dynamic> toJson() => {
        'name': name,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  factory ReportProfile.fromJson(Map<String, dynamic> json) => ReportProfile(
        name: json['name'] as String? ?? 'Custom',
        fields: (json['fields'] as List? ?? const [])
            .map((item) => ReportField.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class ReportProfileService {
  static const _customProfileKey = 'wellwerks_custom_report_profile';

  static const allFields = [
    ReportField(key: 'tbg', label: 'TBG'),
    ReportField(key: 'csg', label: 'CSG'),
    ReportField(key: 'icp', label: 'ICP'),
    ReportField(key: 'scp', label: 'SCP'),
    ReportField(key: 'choke', label: 'Choke'),
    ReportField(key: 'waterRate', label: 'H2O'),
    ReportField(key: 'oilRate', label: 'Oil'),
    ReportField(key: 'gasRate', label: 'Sales RT'),
    ReportField(key: 'diff', label: 'Diff'),
    ReportField(key: 'sp', label: 'SP'),
    ReportField(key: 'gasTemp', label: 'Gas TMP'),
    ReportField(key: 'whTemp', label: 'WH TMP'),
    ReportField(key: 'waterTemp', label: 'H2O TMP'),
    ReportField(key: 'prop', label: 'Prop'),
    ReportField(key: 'biocide', label: 'Biocide'),
    ReportField(key: 'ecdTemp', label: 'ECD Temp'),
    ReportField(key: 'notes', label: 'Notes'),
  ];

  ReportProfile builtIn(String name) {
    if (name == 'Continental') {
      return ReportProfile(
        name: 'Continental',
        fields: allFields.map((f) => f.copyWith(included: true, required: ['csg', 'waterRate', 'oilRate', 'gasRate', 'choke'].contains(f.key))).toList(),
      );
    }
    if (name == 'Mach Energy') {
      final keys = ['choke', 'csg', 'waterRate', 'oilRate', 'gasRate', 'notes'];
      return ReportProfile(
        name: 'Mach Energy',
        fields: allFields.where((f) => keys.contains(f.key)).map((f) => f.copyWith(required: ['choke', 'csg', 'waterRate', 'oilRate', 'gasRate'].contains(f.key))).toList(),
      );
    }
    return ReportProfile(name: 'Custom', fields: allFields);
  }

  Future<ReportProfile> loadCustomProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customProfileKey);
    if (raw == null || raw.isEmpty) return builtIn('Custom');
    return ReportProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveCustomProfile(ReportProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customProfileKey, jsonEncode(profile.toJson()));
  }
}
