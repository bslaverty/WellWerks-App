class FlywheelWellLineData {
  const FlywheelWellLineData({
    required this.wellName,
    required this.tubing,
    required this.csg,
    required this.choke,
    required this.oil,
    required this.water,
    required this.diff,
    required this.stat,
    required this.temp,
    required this.mcf,
    required this.sand,
  });

  final String wellName;
  final String tubing;
  final String csg;
  final String choke;
  final String oil;
  final String water;
  final String diff;
  final String stat;
  final String temp;
  final String mcf;
  final String sand;
}

String buildFlywheelTextUpdate({
  required String updateLine,
  required String locationLine,
  required List<FlywheelWellLineData> wells,
}) {
  final lines = <String>[updateLine.trim()];

  if (locationLine.trim().isNotEmpty) {
    lines.add(locationLine.trim());
  }

  if (wells.isNotEmpty) {
    lines.add('');
  }

  for (var i = 0; i < wells.length; i++) {
    final well = wells[i];
    lines.add(well.wellName.trim().isEmpty ? 'Well' : well.wellName.trim());
    lines.add('Tubing ${_safe(well.tubing)}');
    lines.add('CSG- ${_safe(well.csg)}');
    lines.add('Ck- ${_safe(well.choke)}');
    lines.add('Oil- ${_safe(well.oil)}');
    lines.add('Wtr- ${_safe(well.water)}');
    lines.add('Diff- ${_safe(well.diff)}');
    lines.add('Stat- ${_safe(well.stat)}');
    lines.add('Temp- ${_safe(well.temp)}');
    lines.add('MCF- ${_safe(well.mcf)}');
    lines.add('Sand ${_safe(well.sand)} cup/hr');

    if (i != wells.length - 1) {
      lines.add('');
    }
  }

  return lines.join('\n');
}

String _safe(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '-' : trimmed;
}
