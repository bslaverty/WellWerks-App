import '../services/report_profile_service.dart';

class ReportFieldMeta {
  const ReportFieldMeta({
    required this.key,
    required this.label,
    required this.unit,
    this.machLabel,
    this.continentalLabel,
    this.emailLabel,
  });

  final String key;
  final String label;
  final String unit;
  final String? machLabel;
  final String? continentalLabel;
  final String? emailLabel;

  String labelFor(String company, {bool email = false}) {
    if (email && emailLabel != null) return emailLabel!;
    if (company == 'Mach Energy' && machLabel != null) return machLabel!;
    if (company == 'Continental' && continentalLabel != null) return continentalLabel!;
    return label;
  }
}

class ReportFieldFormatter {
  static const Map<String, ReportFieldMeta> meta = {
    'tbg': ReportFieldMeta(key: 'tbg', label: 'TBG', emailLabel: 'Tubing Pressure', unit: 'psi'),
    'csg': ReportFieldMeta(key: 'csg', label: 'CSG', emailLabel: 'Casing Pressure', unit: 'psi'),
    'icp': ReportFieldMeta(key: 'icp', label: 'ICP', unit: 'psi'),
    'scp': ReportFieldMeta(key: 'scp', label: 'SCP', unit: 'psi'),
    'choke': ReportFieldMeta(key: 'choke', label: 'Chk', machLabel: 'Choke', emailLabel: 'Choke', unit: ''),
    'waterRate': ReportFieldMeta(key: 'waterRate', label: 'H2O', machLabel: 'Water/hr', emailLabel: 'Water Rate', unit: 'bbls/hr'),
    'oilRate': ReportFieldMeta(key: 'oilRate', label: 'Oil', emailLabel: 'Oil Rate', unit: 'bbls/hr'),
    'gasRate': ReportFieldMeta(key: 'gasRate', label: 'Sales RT', machLabel: 'Gas', emailLabel: 'Gas Rate', unit: 'mcf/d'),
    'diff': ReportFieldMeta(key: 'diff', label: 'Diff', emailLabel: 'Differential', unit: '"'),
    'sp': ReportFieldMeta(key: 'sp', label: 'SP', emailLabel: 'Separator Pressure', unit: 'psi'),
    'gasTemp': ReportFieldMeta(key: 'gasTemp', label: 'Gas TMP', emailLabel: 'Gas Temp', unit: '°'),
    'whTemp': ReportFieldMeta(key: 'whTemp', label: 'WH TMP', emailLabel: 'Wellhead Temp', unit: '°'),
    'waterTemp': ReportFieldMeta(key: 'waterTemp', label: 'H2O TMP', emailLabel: 'Water Temp', unit: '°'),
    'prop': ReportFieldMeta(key: 'prop', label: 'Prop', emailLabel: 'Prop Rate', unit: 'gal/hr'),
    'biocide': ReportFieldMeta(key: 'biocide', label: 'Biocide', emailLabel: 'Biocide Rate', unit: 'gal/day'),
    'ecdTemp': ReportFieldMeta(key: 'ecdTemp', label: 'ECD Temp', unit: '°'),
    'notes': ReportFieldMeta(key: 'notes', label: 'Notes', unit: ''),
  };

  static String unitFor(String key) => meta[key]?.unit ?? '';

  static String labelFor(ReportField field, String company, {bool email = false}) {
    return meta[field.key]?.labelFor(company, email: email) ?? field.label;
  }

  static bool isBlank(String value) {
    final text = value.trim();
    return text.isEmpty || text == 'N/A';
  }

  static String withUnit(String key, String value) {
    final text = value.trim();
    if (text.isEmpty) return text;
    final unit = unitFor(key);
    if (unit.isEmpty) return text;
    if (unit == '°') return '$text°';
    if (unit == '"') return '$text"';
    if (text.toLowerCase().endsWith(unit.toLowerCase())) return text;
    return '$text $unit';
  }

  static String line({
    required ReportField field,
    required String value,
    required String company,
    bool email = false,
  }) {
    if (isBlank(value) && !field.required) return '';
    final normalizedValue = isBlank(value) ? 'N/A' : value.trim();
    if (field.key == 'notes') {
      if (normalizedValue == 'N/A') return '';
      return email ? 'Notes: $normalizedValue' : 'Notes- $normalizedValue';
    }
    final label = labelFor(field, company, email: email);
    final formattedValue = withUnit(field.key, normalizedValue);

    if (email) return '$label: $formattedValue';
    if (company == 'Mach Energy' && field.key == 'gasRate') {
      return '$formattedValue 24/hr gas rate';
    }
    if (company == 'Mach Energy' && field.key == 'choke') {
      return '$label $formattedValue';
    }
    return '$label- $formattedValue';
  }
}
