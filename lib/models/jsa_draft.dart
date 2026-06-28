class JsaEmployee {
  JsaEmployee({
    this.name = '',
    this.company = '',
    this.signaturePngBase64,
  });

  String name;
  String company;
  String? signaturePngBase64;

  Map<String, dynamic> toJson() => {
        'name': name,
        'company': company,
        'signaturePngBase64': signaturePngBase64,
      };

  factory JsaEmployee.fromJson(Map<String, dynamic> json) => JsaEmployee(
        name: json['name'] as String? ?? '',
        company: json['company'] as String? ?? '',
        signaturePngBase64: json['signaturePngBase64'] as String?,
      );
}

class JsaDraft {
  JsaDraft({
    required this.company,
    required this.date,
    required this.time,
    required this.location,
    required this.wellName,
    required this.task,
    required this.steps,
    required this.hazards,
    required this.recommendations,
    required this.employees,
    required this.notes,
  });

  String company;
  String date;
  String time;
  String location;
  String wellName;
  String task;
  List<String> steps;
  List<String> hazards;
  List<String> recommendations;
  List<JsaEmployee> employees;
  String notes;

  Map<String, dynamic> toJson() => {
        'company': company,
        'date': date,
        'time': time,
        'location': location,
        'wellName': wellName,
        'task': task,
        'steps': steps,
        'hazards': hazards,
        'recommendations': recommendations,
        'employees': employees.map((e) => e.toJson()).toList(),
        'notes': notes,
      };

  factory JsaDraft.fromJson(Map<String, dynamic> json) => JsaDraft(
        company: json['company'] as String? ?? '',
        date: json['date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        location: json['location'] as String? ?? '',
        wellName: json['wellName'] as String? ?? '',
        task: json['task'] as String? ?? '',
        steps: List<String>.from(json['steps'] as List? ?? const []),
        hazards: List<String>.from(json['hazards'] as List? ?? const []),
        recommendations: List<String>.from(json['recommendations'] as List? ?? const []),
        employees: (json['employees'] as List? ?? const [])
            .map((e) => JsaEmployee.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        notes: json['notes'] as String? ?? '',
      );
}
