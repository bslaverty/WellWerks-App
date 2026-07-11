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

class JobProfileDefaultsService {
  static const String companyContinental = 'Continental Resources';
  static const String companyMach = 'Mach Energy';
  static const String companyFlywheel = 'Flywheel Energy';
  static const String companyCustom = 'Custom';

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
    'RISER',
    'CLR FLARE',
    'VRU',
    'Notes',
  ];

  static const Map<String, String> _continentalReportLabels = <String, String>{
    'csg': 'CSG',
    'icp': 'ICP',
    'chk': 'CHK',
    'bwph': 'H2O',
    'boph': 'OIL',
    'gasSpotRt': 'SALES Rt',
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
    'boph': 'Oil',
    'gasSpotRt': '24/hr gas rate',
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
    'gasSpotRt': 'MCF',
    'prop': 'Sand',
  };

  static const Map<String, String> _continentalTextLabels = <String, String>{
    'csg': 'CSG',
    'icp': 'ICP',
    'chk': 'CHK',
    'bwph': 'H2O',
    'boph': 'OIL',
    'gasSpotRt': 'SALES Rt',
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
    'gasSpotRt': 'GAS',
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
    'gasSpotRt': 'MCF',
    'prop': 'Sand',
  };

  static const Map<String, List<String>> _continentalEquipmentFields =
      <String, List<String>>{
    'RISER': <String>['Temp', 'PL'],
    'CLR FLARE': <String>['Pilot', 'FLARE Rt', 'Temp'],
    'VRU': <String>['GAS RT', 'SUCT', 'DISC'],
    'Notes': <String>['Notes'],
  };

  static const Map<String, List<String>> _machEquipmentFields =
      <String, List<String>>{
    'VRU': <String>['GAS RT', 'SUCT', 'DISC'],
    'Notes': <String>['Notes'],
  };

  static const Map<String, List<String>> _flywheelEquipmentFields =
      <String, List<String>>{
    'Notes': <String>['Notes'],
  };

  static const Map<String, List<String>> _customEquipmentFields =
      <String, List<String>>{
    'Notes': <String>['Notes'],
  };

  String normalizeCompany(String company) {
    final lower = company.trim().toLowerCase();
    if (lower == 'continental' || lower == 'continental resources') {
      return companyContinental;
    }
    if (lower == 'mach energy' || lower == 'mach') {
      return companyMach;
    }
    if (lower == 'flywheel energy' || lower == 'flywheel') {
      return companyFlywheel;
    }
    if (lower.isEmpty || lower == 'custom') {
      return companyCustom;
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

    if (normalized == companyContinental) {
      return const JobProfileDefaults(
        company: companyContinental,
        wellFieldKeys: _continentalWellFields,
        optionalSections: _defaultSections,
        defaultActiveSections: <String>['RISER', 'CLR FLARE', 'VRU', 'Notes'],
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
        defaultActiveSections: <String>['VRU', 'Notes'],
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
        defaultActiveSections: <String>['Notes'],
        reportLabels: _flywheelReportLabels,
        textLabels: _flywheelTextLabels,
        equipmentSectionFields: _flywheelEquipmentFields,
      );
    }

    return const JobProfileDefaults(
      company: companyCustom,
      wellFieldKeys: <String>[
        'chk',
        'csg',
        'bwph',
        'boph',
        'gasSpotRt',
        'prop',
      ],
      optionalSections: _defaultSections,
      defaultActiveSections: <String>['Notes'],
      reportLabels: <String, String>{
        'chk': 'CHK',
        'csg': 'CSG',
        'bwph': 'WTR',
        'boph': 'OIL',
        'gasSpotRt': 'GAS',
        'prop': 'SAND',
      },
      textLabels: <String, String>{
        'chk': 'CHK',
        'csg': 'CSG',
        'bwph': 'WTR',
        'boph': 'OIL',
        'gasSpotRt': 'GAS',
        'prop': 'SAND',
      },
      equipmentSectionFields: _customEquipmentFields,
    );
  }
}
