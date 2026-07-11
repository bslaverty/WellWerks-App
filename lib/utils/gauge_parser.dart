double parseGaugeInput(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return 0;

  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length == 2 && parts[1].contains('/')) {
    final whole = double.tryParse(parts[0]) ?? 0;
    final frac = parts[1].split('/');
    final numerator = double.tryParse(frac.first) ?? 0;
    final denominator = frac.length > 1 ? (double.tryParse(frac[1]) ?? 1) : 1;
    return whole + (numerator / denominator);
  }

  if (clean.contains('/')) {
    final frac = clean.split('/');
    final numerator = double.tryParse(frac.first) ?? 0;
    final denominator = frac.length > 1 ? (double.tryParse(frac[1]) ?? 1) : 1;
    return numerator / denominator;
  }

  return double.tryParse(clean) ?? 0;
}
