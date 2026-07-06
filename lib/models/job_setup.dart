class JobSetup {
  static const _unset = Object();

  JobSetup({
    this.id = '',
    this.company = 'Mach Energy',
    this.jobType = 'singleWell',
    this.customer = '',
    this.padName = '',
    this.notes = '',
    this.leaseName = '',
    this.county = '',
    this.state = '',
    this.crew = '',
    this.shift = 'Day',
    this.dateStarted = '',
    this.status = 'active',
    this.startedAt,
    this.endedAt,
    this.wells = const [],
    this.wellFieldKeys = const [],
    this.activeEquipmentSections = const [],
    this.sandSeparators = 0,
    this.plugCatchers = 0,
    this.chokeManifolds = 0,
    this.lineHeaters = 0,
    this.testUnits = 0,
    this.ecds = 0,
    this.vrus = 0,
    this.flares = 0,
    this.transferPumps = 0,
    this.oilTanks = 0,
    this.oilTankCapacity = '400',
    this.waterTanks = 0,
    this.waterTankCapacity = '500',
    this.productionTankFactor = '1.67',
    this.reportTimes = const [
      '6:00 AM',
      '9:00 AM',
      '12:00 PM',
      '3:00 PM',
      '6:00 PM'
    ],
  });

  final String id;
  final String company;
  final String jobType;
  final String customer;
  final String padName;
  final String notes;
  final String leaseName;
  final String county;
  final String state;
  final String crew;
  final String shift;
  final String dateStarted;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<String> wells;
  final List<String> wellFieldKeys;
  final List<String> activeEquipmentSections;
  final int sandSeparators;
  final int plugCatchers;
  final int chokeManifolds;
  final int lineHeaters;
  final int testUnits;
  final int ecds;
  final int vrus;
  final int flares;
  final int transferPumps;
  final int oilTanks;
  final String oilTankCapacity;
  final int waterTanks;
  final String waterTankCapacity;
  final String productionTankFactor;
  final List<String> reportTimes;

  String get primaryWell => wells.isEmpty ? '' : wells.first;
  String get well => primaryWell;
  bool get isMultiWellJob => jobType == 'multiWellPad';
  bool get isActive => status == 'active';
  bool get isEnded => status == 'ended';

  JobSetup copyWith({
    String? id,
    String? company,
    String? jobType,
    String? customer,
    String? padName,
    String? notes,
    String? leaseName,
    String? county,
    String? state,
    String? crew,
    String? shift,
    String? dateStarted,
    String? status,
    Object? startedAt = _unset,
    Object? endedAt = _unset,
    List<String>? wells,
    List<String>? wellFieldKeys,
    List<String>? activeEquipmentSections,
    int? sandSeparators,
    int? plugCatchers,
    int? chokeManifolds,
    int? lineHeaters,
    int? testUnits,
    int? ecds,
    int? vrus,
    int? flares,
    int? transferPumps,
    int? oilTanks,
    String? oilTankCapacity,
    int? waterTanks,
    String? waterTankCapacity,
    String? productionTankFactor,
    List<String>? reportTimes,
  }) {
    return JobSetup(
      id: id ?? this.id,
      company: company ?? this.company,
      jobType: jobType ?? this.jobType,
      customer: customer ?? this.customer,
      padName: padName ?? this.padName,
      notes: notes ?? this.notes,
      leaseName: leaseName ?? this.leaseName,
      county: county ?? this.county,
      state: state ?? this.state,
      crew: crew ?? this.crew,
      shift: shift ?? this.shift,
      dateStarted: dateStarted ?? this.dateStarted,
      status: status ?? this.status,
      startedAt: startedAt == _unset ? this.startedAt : startedAt as DateTime?,
      endedAt: endedAt == _unset ? this.endedAt : endedAt as DateTime?,
      wells: wells ?? this.wells,
      wellFieldKeys: wellFieldKeys ?? this.wellFieldKeys,
      activeEquipmentSections:
          activeEquipmentSections ?? this.activeEquipmentSections,
      sandSeparators: sandSeparators ?? this.sandSeparators,
      plugCatchers: plugCatchers ?? this.plugCatchers,
      chokeManifolds: chokeManifolds ?? this.chokeManifolds,
      lineHeaters: lineHeaters ?? this.lineHeaters,
      testUnits: testUnits ?? this.testUnits,
      ecds: ecds ?? this.ecds,
      vrus: vrus ?? this.vrus,
      flares: flares ?? this.flares,
      transferPumps: transferPumps ?? this.transferPumps,
      oilTanks: oilTanks ?? this.oilTanks,
      oilTankCapacity: oilTankCapacity ?? this.oilTankCapacity,
      waterTanks: waterTanks ?? this.waterTanks,
      waterTankCapacity: waterTankCapacity ?? this.waterTankCapacity,
      productionTankFactor: productionTankFactor ?? this.productionTankFactor,
      reportTimes: reportTimes ?? this.reportTimes,
    );
  }

  Map<String, dynamic> toJson() => {
        'company': company,
        'id': id,
        'customer': customer,
        'padName': padName,
        'jobType': jobType,
        'notes': notes,
        'leaseName': leaseName,
        'county': county,
        'state': state,
        'crew': crew,
        'shift': shift,
        'dateStarted': dateStarted,
        'status': status,
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'wells': wells,
        'wellFieldKeys': wellFieldKeys,
        'activeEquipmentSections': activeEquipmentSections,
        'sandSeparators': sandSeparators,
        'plugCatchers': plugCatchers,
        'chokeManifolds': chokeManifolds,
        'lineHeaters': lineHeaters,
        'testUnits': testUnits,
        'ecds': ecds,
        'vrus': vrus,
        'flares': flares,
        'transferPumps': transferPumps,
        'oilTanks': oilTanks,
        'oilTankCapacity': oilTankCapacity,
        'waterTanks': waterTanks,
        'waterTankCapacity': waterTankCapacity,
        'productionTankFactor': productionTankFactor,
        'reportTimes': reportTimes,
      };

  factory JobSetup.fromJson(Map<String, dynamic> json) => JobSetup(
        id: json['id'] as String? ?? '',
        company: json['company'] as String? ?? 'Mach Energy',
        jobType: json['jobType'] as String? ?? 'singleWell',
        customer: json['customer'] as String? ?? '',
        padName: json['padName'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        leaseName: json['leaseName'] as String? ?? '',
        county: json['county'] as String? ?? '',
        state: json['state'] as String? ?? '',
        crew: json['crew'] as String? ?? '',
        shift: json['shift'] as String? ?? 'Day',
        dateStarted: json['dateStarted'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
        wells: List<String>.from(json['wells'] as List? ?? const []),
        wellFieldKeys:
            List<String>.from(json['wellFieldKeys'] as List? ?? const []),
        activeEquipmentSections: List<String>.from(
          json['activeEquipmentSections'] as List? ?? const [],
        ),
        sandSeparators: json['sandSeparators'] as int? ?? 0,
        plugCatchers: json['plugCatchers'] as int? ?? 0,
        chokeManifolds: json['chokeManifolds'] as int? ?? 0,
        lineHeaters: json['lineHeaters'] as int? ?? 0,
        testUnits: json['testUnits'] as int? ?? 0,
        ecds: json['ecds'] as int? ?? 0,
        vrus: json['vrus'] as int? ?? 0,
        flares: json['flares'] as int? ?? 0,
        transferPumps: json['transferPumps'] as int? ?? 0,
        oilTanks: json['oilTanks'] as int? ?? 0,
        oilTankCapacity: json['oilTankCapacity'] as String? ?? '400',
        waterTanks: json['waterTanks'] as int? ?? 0,
        waterTankCapacity: json['waterTankCapacity'] as String? ?? '500',
        productionTankFactor: json['productionTankFactor'] as String? ?? '1.67',
        reportTimes: List<String>.from(json['reportTimes'] as List? ??
            const ['6:00 AM', '9:00 AM', '12:00 PM', '3:00 PM', '6:00 PM']),
      );
}
