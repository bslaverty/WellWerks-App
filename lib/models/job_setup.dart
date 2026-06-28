class JobSetup {
  JobSetup({
    this.company = 'Mach Energy',
    this.customer = '',
    this.padName = '',
    this.leaseName = '',
    this.county = '',
    this.state = '',
    this.crew = '',
    this.shift = 'Day',
    this.dateStarted = '',
    this.wells = const [],
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
    this.reportTimes = const ['6:00 AM', '9:00 AM', '12:00 PM', '3:00 PM', '6:00 PM'],
  });

  final String company;
  final String customer;
  final String padName;
  final String leaseName;
  final String county;
  final String state;
  final String crew;
  final String shift;
  final String dateStarted;
  final List<String> wells;
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

  Map<String, dynamic> toJson() => {
        'company': company,
        'customer': customer,
        'padName': padName,
        'leaseName': leaseName,
        'county': county,
        'state': state,
        'crew': crew,
        'shift': shift,
        'dateStarted': dateStarted,
        'wells': wells,
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
        company: json['company'] as String? ?? 'Mach Energy',
        customer: json['customer'] as String? ?? '',
        padName: json['padName'] as String? ?? '',
        leaseName: json['leaseName'] as String? ?? '',
        county: json['county'] as String? ?? '',
        state: json['state'] as String? ?? '',
        crew: json['crew'] as String? ?? '',
        shift: json['shift'] as String? ?? 'Day',
        dateStarted: json['dateStarted'] as String? ?? '',
        wells: List<String>.from(json['wells'] as List? ?? const []),
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
        reportTimes: List<String>.from(json['reportTimes'] as List? ?? const ['6:00 AM', '9:00 AM', '12:00 PM', '3:00 PM', '6:00 PM']),
      );
}
