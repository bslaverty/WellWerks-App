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
    required this.company,
    required this.date,
    required this.time,
    required this.location,
    required this.wellName,
    required this.task,
    List<String>? tasks,
    required this.steps,
    required this.hazards,
    required this.recommendations,
    required this.employees,
    required this.notes,
  }) : tasks = tasks ?? (task.isEmpty ? <String>[] : <String>[task]);

  String activeJobId;
  String company;
  String date;
  String time;
  String location;
  String wellName;
  String task;
  List<String> tasks;
  List<String> steps;
  List<String> hazards;
  List<String> recommendations;
  List<JsaEmployee> employees;
  String notes;

  Map<String, dynamic> toJson() => {
        'activeJobId': activeJobId,
        'company': company,
        'date': date,
        'time': time,
        'location': location,
        'wellName': wellName,
        'task': task,
        'tasks': tasks,
        'steps': steps,
        'hazards': hazards,
        'recommendations': recommendations,
        'employees': employees.map((e) => e.toJson()).toList(),
        'notes': notes,
      };

  factory JsaDraft.fromJson(Map<String, dynamic> json) => JsaDraft(
        activeJobId: json['activeJobId'] as String? ?? '',
        company: json['company'] as String? ?? '',
        date: json['date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        location: json['location'] as String? ?? '',
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
      );
}
