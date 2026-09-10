/// Casing OD/Weight -> ID lookup used by the BTS Calculator to determine
/// annular capacity. Values are standard nominal API casing dimensions.
class CasingWeightOption {
  final double weight;
  final double id;

  const CasingWeightOption({required this.weight, required this.id});

  String get label => '${weight.toStringAsFixed(1)} lb/ft';
}

class CasingSizeOption {
  final String label;
  final double od;
  final List<CasingWeightOption> weights;

  const CasingSizeOption({
    required this.label,
    required this.od,
    required this.weights,
  });
}

class CasingDatabase {
  CasingDatabase._();

  static const List<CasingSizeOption> sizes = [
    CasingSizeOption(
      label: '4-1/2" Casing',
      od: 4.5,
      weights: [
        CasingWeightOption(weight: 9.5, id: 4.090),
        CasingWeightOption(weight: 11.6, id: 4.000),
        CasingWeightOption(weight: 13.5, id: 3.920),
      ],
    ),
    CasingSizeOption(
      label: '5" Casing',
      od: 5.0,
      weights: [
        CasingWeightOption(weight: 15.0, id: 4.408),
        CasingWeightOption(weight: 18.0, id: 4.276),
        CasingWeightOption(weight: 21.4, id: 4.154),
      ],
    ),
    CasingSizeOption(
      label: '5-1/2" Casing',
      od: 5.5,
      weights: [
        CasingWeightOption(weight: 15.5, id: 4.950),
        CasingWeightOption(weight: 17.0, id: 4.892),
        CasingWeightOption(weight: 20.0, id: 4.778),
        CasingWeightOption(weight: 23.0, id: 4.670),
      ],
    ),
    CasingSizeOption(
      label: '7" Casing',
      od: 7.0,
      weights: [
        CasingWeightOption(weight: 20.0, id: 6.456),
        CasingWeightOption(weight: 23.0, id: 6.366),
        CasingWeightOption(weight: 26.0, id: 6.276),
        CasingWeightOption(weight: 29.0, id: 6.184),
        CasingWeightOption(weight: 32.0, id: 6.094),
        CasingWeightOption(weight: 35.0, id: 6.004),
      ],
    ),
    CasingSizeOption(
      label: '9-5/8" Casing',
      od: 9.625,
      weights: [
        CasingWeightOption(weight: 36.0, id: 8.921),
        CasingWeightOption(weight: 40.0, id: 8.835),
        CasingWeightOption(weight: 43.5, id: 8.755),
        CasingWeightOption(weight: 47.0, id: 8.681),
        CasingWeightOption(weight: 53.5, id: 8.535),
      ],
    ),
  ];
}
