import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JobProfileDefaults {
  const JobProfileDefaults({
    required this.company,
    required this.wellFieldKeys,
    required this.optionalSections,
    required this.defaultActiveSections,
    required this.reportLabels,
    required this.textLabels,
    required this.equipmentSectionFields,
  });

  final String company;
  final List<String> wellFieldKeys;
  final List<String> optionalSections;
  final List<String> defaultActiveSections;
  final Map<String, String> reportLabels;
  final Map<String, String> textLabels;
  final Map<String, List<String>> equipmentSectionFields;
}

class CompanyProfileSettings {
  const CompanyProfileSettings({
    required this.name,
    required this.templateCompany,
    required this.defaultActiveSections,
  });

  final String name;
  final String templateCompany;
  final List<String> defaultActiveSections;

  CompanyProfileSettings copyWith({
    String? name,
    String? templateCompany,
    List<String>? defaultActiveSections,
  }) {
    return CompanyProfileSettings(
      name: name ?? this.name,
      templateCompany: templateCompany ?? this.templateCompany,
      defaultActiveSections:
          defaultActiveSections ?? this.defaultActiveSections,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'templateCompany': templateCompany,
        'defaultActiveSections': defaultActiveSections,
      };

  factory CompanyProfileSettings.fromJson(Map<String, dynamic> json) {
    final rawName = (json['name'] as String? ?? '').trim();
    final rawTemplate = (json['templateCompany'] as String? ?? '').trim();
    final rawSections = (json['defaultActiveSections'] as List? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();

    return CompanyProfileSettings(
      name: rawName,
      templateCompany: rawTemplate,
      defaultActiveSections: rawSections,
    );
  }
}

class JobProfileDefaultsService {
  static const String _customProfilesKey = 'wellwerks_company_profiles_v1';
  static const String companyNone = 'None';
  static const String companyContinental = 'Continental Resources';
  static const String companyMach = 'Mach Energy';
  static const String companyFlywheel = 'Flywheel Energy';
  static const String companyValidus = 'Validus Production';
  static const String companyDevon = 'Devon';
  static const String companyXto = 'XTO';

  static const List<String> productionCompanyProfiles = <String>[
    companyMach,
    companyContinental,
    companyFlywheel,
    companyValidus,
  ];

  static const List<String> sharedCompanyOptions = <String>[
    companyNone,
    companyMach,
    companyContinental,
    companyDevon,
    companyFlywheel,
    companyValidus,
    companyXto,
  ];

  static const List<String> sharedCompanyOptionsAlphabetized = <String>[
    companyNone,
    companyContinental,
    companyDevon,
    companyFlywheel,
    companyMach,
    companyValidus,
    companyXto,
  ];

  static final ValueNotifier<List<CompanyProfileSettings>>
      customProfilesNotifier = ValueNotifier<List<CompanyProfileSettings>>(
          const <CompanyProfileSettings>[]);

  static bool _customProfilesLoaded = false;
  static final Map<String, CompanyProfileSettings> _customProfilesByLower =
      <String, CompanyProfileSettings>{};

  static const String jobTypeSingleWell = 'singleWell';
  static const String jobTypeMultiWellPad = 'multiWellPad';

  static const List<String> _continentalWellFields = <String>[
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
  ];

  static const List<String> _machWellFields = <String>[
    'chk',
    'csg',
    'bwph',
    'boph',
    'gasSpotRt',
    'prop',
  ];

  static const List<String> _flywheelWellFields = <String>[
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

  static const List<String> _defaultSections = <String>[
    'FLARE / ECD',
    'VRU',
    'Compressor',
    'Gas Cooler',
    'Water Cooler',
    'Transfer Pump',
  ];

  static const List<String> optionalEquipmentSections = _defaultSections;

  static const Map<String, String> _continentalReportLabels = <String, String>{
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
  };

  static const Map<String, String> _machReportLabels = <String, String>{
    'chk': 'Choke',
    'csg': 'Csg',
    'bwph': 'Wtr/hr',
    'boph': 'Oil/hr',
    'gasSpotRt': 'Gas Rate',
    'prop': 'Sand',
  };

  static const Map<String, String> _flywheelReportLabels = <String, String>{
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

  static const Map<String, String> _continentalTextLabels = <String, String>{
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
  };

  static const Map<String, String> _machTextLabels = <String, String>{
    'chk': 'CHK',
    'csg': 'CSG',
    'bwph': 'WTR',
    'boph': 'OIL',
    'gasSpotRt': 'GAS RATE',
    'prop': 'SAND',
  };

  static const Map<String, String> _flywheelTextLabels = <String, String>{
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

  static const Map<String, List<String>> _continentalEquipmentFields =
      <String, List<String>>{
    'FLARE / ECD': <String>['Temperature', 'Gas Rate'],
    'VRU': <String>['GAS RT', 'SUCT', 'DISC'],
    'Compressor': <String>['COMP INJ'],
    'Gas Cooler': <String>[],
    'Water Cooler': <String>[],
    'Transfer Pump': <String>[],
  };

  static const Map<String, List<String>> _machEquipmentFields =
      <String, List<String>>{
    'FLARE / ECD': <String>['Temperature', 'Gas Rate'],
    'VRU': <String>['GAS RT', 'SUCT', 'DISC'],
    'Compressor': <String>['COMP INJ'],
    'Gas Cooler': <String>[],
    'Water Cooler': <String>[],
    'Transfer Pump': <String>[],
  };

  static const Map<String, List<String>> _flywheelEquipmentFields =
      <String, List<String>>{
    'FLARE / ECD': <String>['Temperature', 'Gas Rate'],
    'Compressor': <String>['COMP INJ'],
    'Gas Cooler': <String>[],
    'Water Cooler': <String>[],
    'Transfer Pump': <String>[],
  };

  static const Map<String, List<String>> _customEquipmentFields =
      <String, List<String>>{
    'FLARE / ECD': <String>['Temperature', 'Gas Rate'],
    'Compressor': <String>['COMP INJ'],
    'Gas Cooler': <String>[],
    'Water Cooler': <String>[],
    'Transfer Pump': <String>[],
  };

  Future<void> ensureCustomProfilesLoaded() async {
    if (_customProfilesLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customProfilesKey);
    if (raw == null || raw.trim().isEmpty) {
      _setCustomProfiles(const <CompanyProfileSettings>[]);
      _customProfilesLoaded = true;
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final profiles = decoded
          .map((item) => CompanyProfileSettings.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .map(_normalizeCustomProfile)
          .where((item) => item != null)
          .cast<CompanyProfileSettings>()
          .toList(growable: false);
      _setCustomProfiles(profiles);
    } catch (_) {
      _setCustomProfiles(const <CompanyProfileSettings>[]);
    }
    _customProfilesLoaded = true;
  }

  Future<void> saveCustomProfiles(List<CompanyProfileSettings> profiles) async {
    final normalized = profiles
        .map(_normalizeCustomProfile)
        .where((item) => item != null)
        .cast<CompanyProfileSettings>()
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customProfilesKey,
      jsonEncode(normalized.map((item) => item.toJson()).toList()),
    );
    _setCustomProfiles(normalized);
    _customProfilesLoaded = true;
  }

  List<CompanyProfileSettings> get customProfiles =>
      List<CompanyProfileSettings>.from(customProfilesNotifier.value);

  List<String> get companyOptions {
    final options = <String>{...sharedCompanyOptionsAlphabetized};
    for (final profile in customProfilesNotifier.value) {
      final name = profile.name.trim();
      if (name.isNotEmpty) {
        options.add(name);
      }
    }
    return options.toList(growable: false);
  }

  static void _setCustomProfiles(List<CompanyProfileSettings> profiles) {
    _customProfilesByLower
      ..clear()
      ..addEntries(
        profiles.map(
          (profile) => MapEntry(profile.name.trim().toLowerCase(), profile),
        ),
      );
    customProfilesNotifier.value =
        List<CompanyProfileSettings>.from(_customProfilesByLower.values);
  }

  CompanyProfileSettings? _normalizeCustomProfile(
      CompanyProfileSettings input) {
    final name = input.name.trim();
    if (name.isEmpty) return null;
    final lower = name.toLowerCase();
    if (lower == companyNone.toLowerCase() || lower == 'custom') return null;

    final template = normalizeCompany(input.templateCompany);
    final baseTemplate = template == companyNone ? companyMach : template;
    final allowed = _defaultSections.toSet();
    final normalizedSections = input.defaultActiveSections
        .map((item) => item.trim())
        .where((item) => allowed.contains(item))
        .toSet()
        .toList(growable: false);

    return CompanyProfileSettings(
      name: name,
      templateCompany: baseTemplate,
      defaultActiveSections: normalizedSections,
    );
  }

  String normalizeCompany(String company) {
    final lower = company.trim().toLowerCase();
    if (lower.isEmpty || lower == 'none' || lower == 'custom') {
      return companyNone;
    }
    if (lower == 'continental' || lower == 'continental resources') {
      return companyContinental;
    }
    if (lower == 'mach energy' || lower == 'mach') {
      return companyMach;
    }
    if (lower == 'flywheel energy' || lower == 'flywheel') {
      return companyFlywheel;
    }
    if (lower == 'validus production' || lower == 'validus') {
      return companyValidus;
    }
    final custom = _customProfilesByLower[lower];
    if (custom != null) {
      return custom.name;
    }
    return company;
  }

  String normalizeJobType(String jobType) {
    return jobType == jobTypeMultiWellPad
        ? jobTypeMultiWellPad
        : jobTypeSingleWell;
  }

  String jobTypeLabel(String jobType) {
    return normalizeJobType(jobType) == jobTypeMultiWellPad
        ? 'Multi-Well / Pad'
        : 'Single Well';
  }

  JobProfileDefaults profileForCompany(String company) {
    final normalized = normalizeCompany(company);

    final custom = _customProfilesByLower[normalized.toLowerCase()];
    if (custom != null) {
      final base = _builtInProfileForCompany(custom.templateCompany);
      return JobProfileDefaults(
        company: custom.name,
        wellFieldKeys: List<String>.from(base.wellFieldKeys),
        optionalSections: List<String>.from(_defaultSections),
        defaultActiveSections: List<String>.from(custom.defaultActiveSections),
        reportLabels: Map<String, String>.from(base.reportLabels),
        textLabels: Map<String, String>.from(base.textLabels),
        equipmentSectionFields:
            Map<String, List<String>>.from(base.equipmentSectionFields),
      );
    }

    return _builtInProfileForCompany(normalized);
  }

  JobProfileDefaults _builtInProfileForCompany(String normalized) {
    if (normalized == companyContinental) {
      return const JobProfileDefaults(
        company: companyContinental,
        wellFieldKeys: _continentalWellFields,
        optionalSections: _defaultSections,
        defaultActiveSections: <String>[],
        reportLabels: _continentalReportLabels,
        textLabels: _continentalTextLabels,
        equipmentSectionFields: _continentalEquipmentFields,
      );
    }

    if (normalized == companyMach) {
      return const JobProfileDefaults(
        company: companyMach,
        wellFieldKeys: _machWellFields,
        optionalSections: _defaultSections,
        defaultActiveSections: <String>[],
        reportLabels: _machReportLabels,
        textLabels: _machTextLabels,
        equipmentSectionFields: _machEquipmentFields,
      );
    }

    if (normalized == companyFlywheel) {
      return const JobProfileDefaults(
        company: companyFlywheel,
        wellFieldKeys: _flywheelWellFields,
        optionalSections: _defaultSections,
        defaultActiveSections: <String>[],
        reportLabels: _flywheelReportLabels,
        textLabels: _flywheelTextLabels,
        equipmentSectionFields: _flywheelEquipmentFields,
      );
    }

    if (normalized == companyValidus) {
      return const JobProfileDefaults(
        company: companyValidus,
        wellFieldKeys: _continentalWellFields,
        optionalSections: _defaultSections,
        defaultActiveSections: <String>[],
        reportLabels: _continentalReportLabels,
        textLabels: _continentalTextLabels,
        equipmentSectionFields: _continentalEquipmentFields,
      );
    }

    return const JobProfileDefaults(
      company: companyNone,
      wellFieldKeys: <String>[
        'chk',
        'csg',
        'bwph',
        'boph',
        'gasSpotRt',
        'prop',
      ],
      optionalSections: _defaultSections,
      defaultActiveSections: <String>[],
      reportLabels: <String, String>{
        'chk': 'CHK',
        'csg': 'CSG',
        'bwph': 'WTR',
        'boph': 'OIL',
        'gasSpotRt': 'GAS RATE',
        'prop': 'SAND',
      },
      textLabels: <String, String>{
        'chk': 'CHK',
        'csg': 'CSG',
        'bwph': 'WTR',
        'boph': 'OIL',
        'gasSpotRt': 'GAS RATE',
        'prop': 'SAND',
      },
      equipmentSectionFields: _customEquipmentFields,
    );
  }

  @visibleForTesting
  static void resetCustomProfilesForTest() {
    _customProfilesLoaded = false;
    _customProfilesByLower.clear();
    customProfilesNotifier.value = const <CompanyProfileSettings>[];
  }
}
