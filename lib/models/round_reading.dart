class RoundReading {
  RoundReading({
    required this.id,
    required this.timestamp,
    this.roundLabel = '',
    this.oilRate = '',
    this.waterRate = '',
    this.gasRate = '',
    this.tubingPressure = '',
    this.casingPressure = '',
    this.icp = '',
    this.scp = '',
    this.separatorPressure = '',
    this.differentialPressure = '',
    this.gasTemp = '',
    this.wellheadTemp = '',
    this.waterTemp = '',
    this.ecdTemp = '',
    this.propRate = '',
    this.biocideRate = '',
    this.choke = '',
    this.chokeStyle = 'adj',
    this.notes = '',
  });

  final String id;
  final DateTime timestamp;
  final String roundLabel;
  final String oilRate;
  final String waterRate;
  final String gasRate;
  final String tubingPressure;
  final String casingPressure;
  final String icp;
  final String scp;
  final String separatorPressure;
  final String differentialPressure;
  final String gasTemp;
  final String wellheadTemp;
  final String waterTemp;
  final String ecdTemp;
  final String propRate;
  final String biocideRate;
  final String choke;
  final String chokeStyle;
  final String notes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'roundLabel': roundLabel,
        'oilRate': oilRate,
        'waterRate': waterRate,
        'gasRate': gasRate,
        'tubingPressure': tubingPressure,
        'casingPressure': casingPressure,
        'icp': icp,
        'scp': scp,
        'separatorPressure': separatorPressure,
        'differentialPressure': differentialPressure,
        'gasTemp': gasTemp,
        'wellheadTemp': wellheadTemp,
        'waterTemp': waterTemp,
        'ecdTemp': ecdTemp,
        'propRate': propRate,
        'biocideRate': biocideRate,
        'choke': choke,
        'chokeStyle': chokeStyle,
        'notes': notes,
      };

  factory RoundReading.fromJson(Map<String, dynamic> json) => RoundReading(
        id: json['id'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        roundLabel: json['roundLabel'] as String? ?? '',
        oilRate: json['oilRate'] as String? ?? '',
        waterRate: json['waterRate'] as String? ?? '',
        gasRate: json['gasRate'] as String? ?? '',
        tubingPressure: json['tubingPressure'] as String? ?? '',
        casingPressure: json['casingPressure'] as String? ?? '',
        icp: json['icp'] as String? ?? '',
        scp: json['scp'] as String? ?? '',
        separatorPressure: json['separatorPressure'] as String? ?? '',
        differentialPressure: json['differentialPressure'] as String? ?? '',
        gasTemp: json['gasTemp'] as String? ?? '',
        wellheadTemp: json['wellheadTemp'] as String? ?? '',
        waterTemp: json['waterTemp'] as String? ?? '',
        ecdTemp: json['ecdTemp'] as String? ?? '',
        propRate: json['propRate'] as String? ?? '',
        biocideRate: json['biocideRate'] as String? ?? '',
        choke: json['choke'] as String? ?? '',
        chokeStyle: json['chokeStyle'] as String? ?? 'adj',
        notes: json['notes'] as String? ?? '',
      );
}
