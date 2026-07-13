class JsaSignaturePoint {
  const JsaSignaturePoint({
    required this.x,
    required this.y,
    required this.type,
    required this.pressure,
  });

  final double x;
  final double y;
  final String type;
  final double pressure;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'type': type,
        'pressure': pressure,
      };

  factory JsaSignaturePoint.fromJson(Map<String, dynamic> json) {
    return JsaSignaturePoint(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      type: json['type'] as String? ?? 'tap',
      pressure: (json['pressure'] as num?)?.toDouble() ?? 1,
    );
  }
}

class JsaEmployee {
  JsaEmployee({
    this.name = '',
    this.company = '',
    this.signaturePngBase64,
    this.signaturePoints = const [],
  });

  String name;
  String company;
  String? signaturePngBase64;
  List<JsaSignaturePoint> signaturePoints;

  Map<String, dynamic> toJson() => {
        'name': name,
        'company': company,
        'signaturePngBase64': signaturePngBase64,
        'signaturePoints':
            signaturePoints.map((item) => item.toJson()).toList(),
      };

  factory JsaEmployee.fromJson(Map<String, dynamic> json) => JsaEmployee(
        name: json['name'] as String? ?? '',
        company: json['company'] as String? ?? '',
        signaturePngBase64: json['signaturePngBase64'] as String?,
        signaturePoints: (json['signaturePoints'] as List? ?? const [])
            .map((item) => JsaSignaturePoint.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class JsaDraft {
  JsaDraft({
    this.activeJobId = '',
    this.templateId = '',
    this.templateName = '',
    required this.company,
    required this.date,
    required this.time,
    required this.location,
    this.county = '',
    this.cityState = '',
    this.gpsCoordinates = '',
    this.wellName = '',
    required this.task,
    List<String>? tasks,
    required this.steps,
    required this.hazards,
    required this.recommendations,
    required this.employees,
    required this.notes,
    this.weatherTemperature = '',
    this.weatherConditions = '',
    this.weatherWind = '',
  }) : tasks = tasks ?? (task.isEmpty ? <String>[] : <String>[task]);

  String activeJobId;
  String templateId;
  String templateName;
  String company;
  String date;
  String time;
  String location;
  String county;
  String cityState;
  String gpsCoordinates;
  String wellName;
  String task;
  List<String> tasks;
  List<String> steps;
  List<String> hazards;
  List<String> recommendations;
  List<JsaEmployee> employees;
  String notes;
  String weatherTemperature;
  String weatherConditions;
  String weatherWind;

  Map<String, dynamic> toJson() => {
        'activeJobId': activeJobId,
        'templateId': templateId,
        'templateName': templateName,
        'company': company,
        'date': date,
        'time': time,
        'location': location,
        'county': county,
        'cityState': cityState,
        'gpsCoordinates': gpsCoordinates,
        'wellName': wellName,
        'task': task,
        'tasks': tasks,
        'steps': steps,
        'hazards': hazards,
        'recommendations': recommendations,
        'employees': employees.map((e) => e.toJson()).toList(),
        'notes': notes,
        'weatherTemperature': weatherTemperature,
        'weatherConditions': weatherConditions,
        'weatherWind': weatherWind,
      };

  factory JsaDraft.fromJson(Map<String, dynamic> json) => JsaDraft(
        activeJobId: json['activeJobId'] as String? ?? '',
        templateId: json['templateId'] as String? ?? '',
        templateName: json['templateName'] as String? ?? '',
        company: json['company'] as String? ?? '',
        date: json['date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        location: json['location'] as String? ?? '',
        county: json['county'] as String? ?? '',
        cityState: json['cityState'] as String? ?? '',
        gpsCoordinates: json['gpsCoordinates'] as String? ?? '',
        wellName: json['wellName'] as String? ?? '',
        task: json['task'] as String? ?? '',
        tasks: List<String>.from(json['tasks'] as List? ??
            (((json['task'] as String? ?? '').isEmpty)
                ? const []
                : [json['task'] as String])),
        steps: List<String>.from(json['steps'] as List? ?? const []),
        hazards: List<String>.from(json['hazards'] as List? ?? const []),
        recommendations:
            List<String>.from(json['recommendations'] as List? ?? const []),
        employees: (json['employees'] as List? ?? const [])
            .map((e) =>
                JsaEmployee.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        notes: json['notes'] as String? ?? '',
        weatherTemperature: json['weatherTemperature'] as String? ?? '',
        weatherConditions: json['weatherConditions'] as String? ?? '',
        weatherWind: json['weatherWind'] as String? ?? '',
      );
}
