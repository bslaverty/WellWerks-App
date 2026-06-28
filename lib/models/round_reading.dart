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
        notes: json['notes'] as String? ?? '',
      );
}
