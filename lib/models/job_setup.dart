class JobSetup {
  static const _unset = Object();
  static const List<String> chemicalOptions = <String>[
    'Biocide',
    'Scavenger',
    'Defoamer',
    'Scale Inhibitor',
  ];

  JobSetup({
    this.id = '',
    this.company = 'Mach Energy',
    this.jobType = 'singleWell',
    this.customer = '',
    this.padName = '',
    this.notes = '',
    this.leaseName = '',
    this.leaseNames = const [],
    this.county = '',
    this.state = '',
    this.crew = '',
    this.shift = 'Day',
    this.dateStarted = '',
    this.status = 'active',
    this.startedAt,
    this.endedAt,
    this.wells = const [],
    this.wellEntries = const [],
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
    this.selectedChemicals = const [],
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
  final List<String> leaseNames;
  final String county;
  final String state;
  final String crew;
  final String shift;
  final String dateStarted;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<String> wells;
  final List<JobSetupWell> wellEntries;
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
  final List<String> selectedChemicals;
  final List<String> reportTimes;

  String get primaryWell => wells.isEmpty ? '' : wells.first;
  List<String> get wellIds {
    if (wellEntries.length == wells.length && wellEntries.isNotEmpty) {
      return wellEntries.map((item) => item.id).toList();
    }
    return [
      for (int i = 0; i < wells.length; i++) legacyWellId(wells[i], i),
    ];
  }

  List<String> get resolvedLeaseNames {
    final fromList = leaseNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (fromList.isNotEmpty) {
      return fromList;
    }
    if (wells.isEmpty) return const <String>[];
    if (leaseName.trim().isEmpty) {
      return List<String>.filled(wells.length, '');
    }
    return [
      leaseName.trim(),
      for (int i = 1; i < wells.length; i++) '',
    ];
  }

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
    List<String>? leaseNames,
    String? county,
    String? state,
    String? crew,
    String? shift,
    String? dateStarted,
    String? status,
    Object? startedAt = _unset,
    Object? endedAt = _unset,
    List<String>? wells,
    List<JobSetupWell>? wellEntries,
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
    List<String>? selectedChemicals,
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
      leaseNames: leaseNames ?? this.leaseNames,
      county: county ?? this.county,
      state: state ?? this.state,
      crew: crew ?? this.crew,
      shift: shift ?? this.shift,
      dateStarted: dateStarted ?? this.dateStarted,
      status: status ?? this.status,
      startedAt: startedAt == _unset ? this.startedAt : startedAt as DateTime?,
      endedAt: endedAt == _unset ? this.endedAt : endedAt as DateTime?,
      wells: wells ?? this.wells,
      wellEntries: wellEntries ?? this.wellEntries,
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
      selectedChemicals: selectedChemicals ?? this.selectedChemicals,
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
        'leaseNames': leaseNames,
        'county': county,
        'state': state,
        'crew': crew,
        'shift': shift,
        'dateStarted': dateStarted,
        'status': status,
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'wells': wells,
        'wellEntries': wellEntries.map((item) => item.toJson()).toList(),
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
        'selectedChemicals': selectedChemicals,
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
        leaseNames: _buildLeaseNames(json),
        county: json['county'] as String? ?? '',
        state: json['state'] as String? ?? '',
        crew: json['crew'] as String? ?? '',
        shift: json['shift'] as String? ?? 'Day',
        dateStarted: json['dateStarted'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
        wells: _buildLegacyWells(json),
        wellEntries: _buildWellEntries(json),
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
        selectedChemicals: _normalizeSelectedChemicals(
          (json['selectedChemicals'] as List?)
                  ?.map((item) => item?.toString() ?? '')
                  .toList() ??
              const <String>[],
        ),
        reportTimes: List<String>.from(json['reportTimes'] as List? ??
            const ['6:00 AM', '9:00 AM', '12:00 PM', '3:00 PM', '6:00 PM']),
      );

  static List<String> _normalizeSelectedChemicals(List<String> selected) {
    final normalized = <String>[];
    for (final option in chemicalOptions) {
      if (selected
          .any((item) => item.trim().toLowerCase() == option.toLowerCase())) {
        normalized.add(option);
      }
    }
    return normalized;
  }

  static List<String> _buildLeaseNames(Map<String, dynamic> json) {
    final fromList = List<String>.from(json['leaseNames'] as List? ?? const [])
        .map((item) => item.trim())
        .toList();
    if (fromList.isNotEmpty) {
      return fromList;
    }

    final legacyLease = (json['leaseName'] as String? ?? '').trim();
    if (legacyLease.isEmpty) {
      return const <String>[];
    }

    final legacyWells = List<String>.from(json['wells'] as List? ?? const []);
    if (legacyWells.isEmpty) {
      return <String>[legacyLease];
    }
    return [
      legacyLease,
      for (int i = 1; i < legacyWells.length; i++) '',
    ];
  }

  static String generateWellId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'well_$micros';
  }

  static String legacyWellId(String name, int index) {
    final normalized = name.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '_',
        );
    final safe = normalized.isEmpty ? 'well_${index + 1}' : normalized;
    return 'legacy_${index + 1}_$safe';
  }

  static List<String> _buildLegacyWells(Map<String, dynamic> json) {
    final entryWells = ((json['wellEntries'] as List?) ?? const [])
        .map((item) => item is Map
            ? JobSetupWell.fromJson(Map<String, dynamic>.from(item)).name
            : '')
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (entryWells.isNotEmpty) {
      return entryWells;
    }
    return List<String>.from(json['wells'] as List? ?? const []);
  }

  static List<JobSetupWell> _buildWellEntries(Map<String, dynamic> json) {
    final rawEntries = ((json['wellEntries'] as List?) ?? const [])
        .map((item) => item is Map
            ? JobSetupWell.fromJson(Map<String, dynamic>.from(item))
            : null)
        .whereType<JobSetupWell>()
        .where((item) => item.name.trim().isNotEmpty)
        .toList();
    final fromEntries = [
      for (int i = 0; i < rawEntries.length; i++)
        rawEntries[i].copyWith(
          id: rawEntries[i].id.trim().isEmpty
              ? legacyWellId(rawEntries[i].name, i)
              : rawEntries[i].id.trim(),
          name: rawEntries[i].name.trim(),
        ),
    ];
    if (fromEntries.isNotEmpty) {
      return fromEntries;
    }

    final legacy = List<String>.from(json['wells'] as List? ?? const []);
    return [
      for (int i = 0; i < legacy.length; i++)
        JobSetupWell(
          id: legacyWellId(legacy[i], i),
          name: legacy[i],
        ),
    ];
  }
}

class JobSetupWell {
  const JobSetupWell({
    required this.id,
    required this.name,
  });

  factory JobSetupWell.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? '').trim();
    final id = (json['id'] as String? ?? '').trim();
    return JobSetupWell(
      id: id,
      name: name,
    );
  }

  final String id;
  final String name;

  JobSetupWell copyWith({
    String? id,
    String? name,
  }) {
    return JobSetupWell(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}
