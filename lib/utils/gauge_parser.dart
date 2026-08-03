double parseGaugeInput(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return 0;

  var normalized = clean;
  var sign = 1.0;
  if (normalized.startsWith('-')) {
    sign = -1.0;
    normalized = normalized.substring(1).trimLeft();
  } else if (normalized.startsWith('+')) {
    normalized = normalized.substring(1).trimLeft();
  }

  if (normalized.isEmpty) return 0;

  final parts = normalized.split(RegExp(r'\s+'));
  if (parts.length == 2 && parts[1].contains('/')) {
    final whole = double.tryParse(parts[0]) ?? 0;
    return sign * (whole + _parseFraction(parts[1]));
  }

  if (normalized.contains('/')) {
    return sign * _parseFraction(normalized);
  }

  return sign * (double.tryParse(normalized) ?? 0);
}

double _parseFraction(String value) {
  final frac = value.split('/');
  final numerator = double.tryParse(frac.first.trim()) ?? 0;
  final denominator =
      frac.length > 1 ? (double.tryParse(frac[1].trim()) ?? 1) : 1;
  if (denominator == 0) return 0;
  return numerator / denominator;
}
