class ProductionShift {
  const ProductionShift({
    required this.header,
    required this.inventory,
    required this.activeJobId,
    required this.roundStartTime,
    required this.checkCount,
    required this.hourlyChecks,
    required this.savedRows,
    this.wellSelectedChokes = const {},
    this.wellSelectedChokeTypes = const {},
    required this.selectedTextHour,
    required this.updatedAt,
  });

  factory ProductionShift.empty() {
    return ProductionShift(
      header: const ProductionShiftHeader(),
      inventory: ProductionInventoryBaseline.empty(),
      activeJobId: '',
      roundStartTime: '6 AM',
      checkCount: 12,
      hourlyChecks: const [],
      savedRows: const [],
      wellSelectedChokes: const {},
      wellSelectedChokeTypes: const {},
      selectedTextHour: null,
      updatedAt: DateTime.now(),
    );
  }

  factory ProductionShift.fromJson(Map<String, dynamic> json) {
    return ProductionShift(
      header: ProductionShiftHeader.fromJson(
        Map<String, dynamic>.from(
          (json['header'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      inventory: ProductionInventoryBaseline.fromJson(
        Map<String, dynamic>.from(
          (json['inventory'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      activeJobId: json['activeJobId'] as String? ?? '',
      roundStartTime: json['roundStartTime'] as String? ?? '6 AM',
      checkCount: json['checkCount'] as int? ?? 12,
      hourlyChecks: ((json['hourlyChecks'] as List?) ?? const [])
          .map((item) => ProductionHourlyCheck.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
      savedRows: ((json['savedRows'] as List?) ?? const [])
          .map((item) => ProductionReportRow.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
      wellSelectedChokes: ((json['wellSelectedChokes'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
      wellSelectedChokeTypes:
          ((json['wellSelectedChokeTypes'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          ProductionShiftHeader._normalizeChokeType(value?.toString()),
        ),
      ),
      selectedTextHour: json['selectedTextHour'] as int?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final ProductionShiftHeader header;
  final ProductionInventoryBaseline inventory;
  final String activeJobId;
  final String roundStartTime;
  final int checkCount;
  final List<ProductionHourlyCheck> hourlyChecks;
  final List<ProductionReportRow> savedRows;
  final Map<String, String> wellSelectedChokes;
  final Map<String, String> wellSelectedChokeTypes;
  final int? selectedTextHour;
  final DateTime updatedAt;

  ProductionShift copyWith({
    ProductionShiftHeader? header,
    ProductionInventoryBaseline? inventory,
    String? activeJobId,
    String? roundStartTime,
    int? checkCount,
    List<ProductionHourlyCheck>? hourlyChecks,
    List<ProductionReportRow>? savedRows,
    Map<String, String>? wellSelectedChokes,
    Map<String, String>? wellSelectedChokeTypes,
    int? selectedTextHour,
    bool clearSelectedTextHour = false,
    DateTime? updatedAt,
  }) {
    return ProductionShift(
      header: header ?? this.header,
      inventory: inventory ?? this.inventory,
      activeJobId: activeJobId ?? this.activeJobId,
      roundStartTime: roundStartTime ?? this.roundStartTime,
      checkCount: checkCount ?? this.checkCount,
      hourlyChecks: hourlyChecks ?? this.hourlyChecks,
      savedRows: savedRows ?? this.savedRows,
      wellSelectedChokes: wellSelectedChokes ?? this.wellSelectedChokes,
      wellSelectedChokeTypes:
          wellSelectedChokeTypes ?? this.wellSelectedChokeTypes,
      selectedTextHour: clearSelectedTextHour
          ? null
          : (selectedTextHour ?? this.selectedTextHour),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'header': header.toJson(),
      'inventory': inventory.toJson(),
      'activeJobId': activeJobId,
      'roundStartTime': roundStartTime,
      'checkCount': checkCount,
      'hourlyChecks': hourlyChecks.map((item) => item.toJson()).toList(),
      'savedRows': savedRows.map((item) => item.toJson()).toList(),
      'wellSelectedChokes': wellSelectedChokes,
      'wellSelectedChokeTypes': wellSelectedChokeTypes,
      'selectedTextHour': selectedTextHour,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class ProductionShiftHeader {
  const ProductionShiftHeader({
    this.company = '',
    this.pad = '',
    this.date = '',
    this.layoutProfileId = 'default',
    this.chokeType = 'ADJ',
    this.wellChokeTypes = const {},
    this.wellIds = const [],
    this.wells = const [],
  });

  factory ProductionShiftHeader.fromJson(Map<String, dynamic> json) {
    final wells = ((json['wells'] as List?) ?? const [])
        .map((item) => item?.toString() ?? '')
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return ProductionShiftHeader(
      company: json['company'] as String? ?? '',
      pad: json['pad'] as String? ?? '',
      date: json['date'] as String? ?? '',
      layoutProfileId:
          (json['layoutProfileId'] as String? ?? 'default').trim().isEmpty
              ? 'default'
              : (json['layoutProfileId'] as String? ?? 'default').trim(),
      chokeType: _normalizeChokeType(json['chokeType'] as String?),
      wellChokeTypes: ((json['wellChokeTypes'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          _normalizeChokeType(value?.toString()),
        ),
      ),
      wellIds: ((json['wellIds'] as List?) ?? const [])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      wells: wells,
    );
  }

  static String _normalizeChokeType(String? value) {
    final upper = (value ?? '').trim().toUpperCase();
    return upper == 'POS' ? 'POS' : 'ADJ';
  }

  final String company;
  final String pad;
  final String date;
  final String layoutProfileId;
  final String chokeType;
  final Map<String, String> wellChokeTypes;
  final List<String> wellIds;
  final List<String> wells;

  ProductionShiftHeader copyWith({
    String? company,
    String? pad,
    String? date,
    String? layoutProfileId,
    String? chokeType,
    Map<String, String>? wellChokeTypes,
    List<String>? wellIds,
    List<String>? wells,
  }) {
    return ProductionShiftHeader(
      company: company ?? this.company,
      pad: pad ?? this.pad,
      date: date ?? this.date,
      layoutProfileId: (layoutProfileId ?? this.layoutProfileId).trim().isEmpty
          ? 'default'
          : (layoutProfileId ?? this.layoutProfileId).trim(),
      chokeType: _normalizeChokeType(chokeType ?? this.chokeType),
      wellChokeTypes: wellChokeTypes ?? this.wellChokeTypes,
      wellIds: wellIds ?? this.wellIds,
      wells: wells ?? this.wells,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'company': company,
      'pad': pad,
      'date': date,
      'layoutProfileId': layoutProfileId,
      'chokeType': chokeType,
      'wellChokeTypes': wellChokeTypes,
      'wellIds': wellIds,
      'wells': wells,
    };
  }
}

class ProductionGaugeEntry {
  const ProductionGaugeEntry({
    this.mode = 'inches',
    this.inches = '',
    this.feet = '',
    this.inchesPart = '',
    this.decimalFeet = '',
  });

  factory ProductionGaugeEntry.fromJson(Map<String, dynamic> json) {
    return ProductionGaugeEntry(
      mode: _normalizeMode(json['mode'] as String?),
      inches: json['inches'] as String? ?? '',
      feet: json['feet'] as String? ?? '',
      inchesPart: json['inchesPart'] as String? ?? '',
      decimalFeet: json['decimalFeet'] as String? ?? '',
    );
  }

  factory ProductionGaugeEntry.fromLegacyGauge(String value) {
    return ProductionGaugeEntry(inches: value.trim());
  }

  static String _normalizeMode(String? value) {
    switch ((value ?? '').trim()) {
      case 'feetInches':
        return 'feetInches';
      case 'decimalFeet':
        return 'decimalFeet';
      default:
        return 'inches';
    }
  }

  final String mode;
  final String inches;
  final String feet;
  final String inchesPart;
  final String decimalFeet;

  double asInches() {
    const asNumber = double.tryParse;
    if (mode == 'feetInches') {
      final feetValue = asNumber(feet.trim()) ?? 0;
      final inchesValue = asNumber(inchesPart.trim()) ?? 0;
      return feetValue * 12 + inchesValue;
    }
    if (mode == 'decimalFeet') {
      final decimalFeetValue = asNumber(decimalFeet.trim()) ?? 0;
      return decimalFeetValue * 12;
    }
    return asNumber(inches.trim()) ?? 0;
  }

  String inchesText() {
    final value = asInches();
    if (value == 0) {
      return '';
    }
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  String entryText() {
    if (mode == 'feetInches') {
      final feetText = feet.trim().isEmpty ? '0' : feet.trim();
      final inchesText = inchesPart.trim().isEmpty ? '0' : inchesPart.trim();
      return '$feetText ft $inchesText in';
    }
    if (mode == 'decimalFeet') {
      return '${decimalFeet.trim().isEmpty ? '0' : decimalFeet.trim()} ft';
    }
    return '${inches.trim().isEmpty ? '0' : inches.trim()} in';
  }

  ProductionGaugeEntry copyWith({
    String? mode,
    String? inches,
    String? feet,
    String? inchesPart,
    String? decimalFeet,
  }) {
    return ProductionGaugeEntry(
      mode: _normalizeMode(mode ?? this.mode),
      inches: inches ?? this.inches,
      feet: feet ?? this.feet,
      inchesPart: inchesPart ?? this.inchesPart,
      decimalFeet: decimalFeet ?? this.decimalFeet,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'inches': inches,
      'feet': feet,
      'inchesPart': inchesPart,
      'decimalFeet': decimalFeet,
    };
  }
}

class ProductionInventoryBaseline {
  const ProductionInventoryBaseline({
    required this.waterTanks,
    required this.oilTanks,
    this.oilInventoryWells = const [],
    this.useStartingReadings = false,
    this.useJobSetupTanks = true,
    this.productionRows = const [],
    this.gaugeEntryType = 'inches',
    this.gasUnit = 'mcfd',
    this.gasCalculationMethod = 'accumulator',
    this.startingGasAccum = '',
    this.waterHauledBeforeRound = '',
    this.oilHauledBeforeRound = '',
    this.waterPumpedBeforeRound = '',
    this.oilPumpedBeforeRound = '',
  });

  factory ProductionInventoryBaseline.empty() {
    return const ProductionInventoryBaseline(
      waterTanks: [ProductionTank(name: 'Water Tank 1')],
      oilTanks: [ProductionTank(name: 'Oil Tank 1')],
    );
  }

  factory ProductionInventoryBaseline.fromJson(Map<String, dynamic> json) {
    final waterTanks = ((json['waterTanks'] as List?) ?? const [])
        .map((item) =>
            ProductionTank.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final oilTanks = ((json['oilTanks'] as List?) ?? const [])
        .map((item) =>
            ProductionTank.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final oilInventoryWells = ((json['oilInventoryWells'] as List?) ?? const [])
        .map((item) => ProductionOilInventoryWell.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
    final productionRows = ((json['productionRows'] as List?) ?? const [])
        .map((item) => ProductionReportRow.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
    final inferredGaugeType = waterTanks.isNotEmpty
        ? waterTanks.first.gaugeEntry.mode
        : (oilTanks.isNotEmpty ? oilTanks.first.gaugeEntry.mode : 'inches');
    return ProductionInventoryBaseline(
      waterTanks: waterTanks.isEmpty
          ? const [ProductionTank(name: 'Water Tank 1')]
          : waterTanks,
      oilTanks: oilTanks.isEmpty
          ? const [ProductionTank(name: 'Oil Tank 1')]
          : oilTanks,
      oilInventoryWells: oilInventoryWells,
      useStartingReadings: json['useStartingReadings'] as bool? ?? false,
      useJobSetupTanks: json['useJobSetupTanks'] as bool? ?? true,
      productionRows: productionRows,
      gaugeEntryType: ProductionGaugeEntry._normalizeMode(
        (json['gaugeEntryType'] as String?) ?? inferredGaugeType,
      ),
      gasUnit: _normalizeGasUnit(json['gasUnit'] as String?),
      gasCalculationMethod: _normalizeGasCalculationMethod(
        json['gasCalculationMethod'] as String?,
      ),
      startingGasAccum: json['startingGasAccum'] as String? ?? '',
      waterHauledBeforeRound: json['waterHauledBeforeRound'] as String? ?? '',
      oilHauledBeforeRound: json['oilHauledBeforeRound'] as String? ?? '',
      waterPumpedBeforeRound: json['waterPumpedBeforeRound'] as String? ?? '',
      oilPumpedBeforeRound: json['oilPumpedBeforeRound'] as String? ?? '',
    );
  }

  final List<ProductionTank> waterTanks;
  final List<ProductionTank> oilTanks;
  final List<ProductionOilInventoryWell> oilInventoryWells;
  final bool useStartingReadings;
  final bool useJobSetupTanks;
  final List<ProductionReportRow> productionRows;
  final String gaugeEntryType;
  final String gasUnit;
  final String gasCalculationMethod;
  final String startingGasAccum;
  final String waterHauledBeforeRound;
  final String oilHauledBeforeRound;
  final String waterPumpedBeforeRound;
  final String oilPumpedBeforeRound;

  ProductionInventoryBaseline copyWith({
    List<ProductionTank>? waterTanks,
    List<ProductionTank>? oilTanks,
    List<ProductionOilInventoryWell>? oilInventoryWells,
    bool? useStartingReadings,
    bool? useJobSetupTanks,
    List<ProductionReportRow>? productionRows,
    String? gaugeEntryType,
    String? gasUnit,
    String? gasCalculationMethod,
    String? startingGasAccum,
    String? waterHauledBeforeRound,
    String? oilHauledBeforeRound,
    String? waterPumpedBeforeRound,
    String? oilPumpedBeforeRound,
  }) {
    return ProductionInventoryBaseline(
      waterTanks: waterTanks ?? this.waterTanks,
      oilTanks: oilTanks ?? this.oilTanks,
      oilInventoryWells: oilInventoryWells ?? this.oilInventoryWells,
      useStartingReadings: useStartingReadings ?? this.useStartingReadings,
      useJobSetupTanks: useJobSetupTanks ?? this.useJobSetupTanks,
      productionRows: productionRows ?? this.productionRows,
      gaugeEntryType: ProductionGaugeEntry._normalizeMode(
        gaugeEntryType ?? this.gaugeEntryType,
      ),
      gasUnit: _normalizeGasUnit(gasUnit ?? this.gasUnit),
      gasCalculationMethod: _normalizeGasCalculationMethod(
        gasCalculationMethod ?? this.gasCalculationMethod,
      ),
      startingGasAccum: startingGasAccum ?? this.startingGasAccum,
      waterHauledBeforeRound:
          waterHauledBeforeRound ?? this.waterHauledBeforeRound,
      oilHauledBeforeRound: oilHauledBeforeRound ?? this.oilHauledBeforeRound,
      waterPumpedBeforeRound:
          waterPumpedBeforeRound ?? this.waterPumpedBeforeRound,
      oilPumpedBeforeRound: oilPumpedBeforeRound ?? this.oilPumpedBeforeRound,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'waterTanks': waterTanks.map((item) => item.toJson()).toList(),
      'oilTanks': oilTanks.map((item) => item.toJson()).toList(),
      'oilInventoryWells':
          oilInventoryWells.map((item) => item.toJson()).toList(),
      'useStartingReadings': useStartingReadings,
      'useJobSetupTanks': useJobSetupTanks,
      'productionRows': productionRows.map((item) => item.toJson()).toList(),
      'gaugeEntryType': gaugeEntryType,
      'gasUnit': gasUnit,
      'gasCalculationMethod': gasCalculationMethod,
      'startingGasAccum': startingGasAccum,
      'waterHauledBeforeRound': waterHauledBeforeRound,
      'oilHauledBeforeRound': oilHauledBeforeRound,
      'waterPumpedBeforeRound': waterPumpedBeforeRound,
      'oilPumpedBeforeRound': oilPumpedBeforeRound,
    };
  }

  static String _normalizeGasUnit(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'mmcfd' ? 'mmcfd' : 'mcfd';
  }

  static String _normalizeGasCalculationMethod(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'manual' ? 'manual' : 'accumulator';
  }
}

class ProductionOilInventoryWell {
  const ProductionOilInventoryWell({
    required this.wellName,
    this.beginningOilInventory = '',
    this.currentOilInventory = '',
    this.expectedOilInventory = '',
    this.currentCushion = '',
    this.maximumCushion = '',
  });

  factory ProductionOilInventoryWell.fromJson(Map<String, dynamic> json) {
    return ProductionOilInventoryWell(
      wellName: json['wellName'] as String? ?? '',
      beginningOilInventory: json['beginningOilInventory'] as String? ?? '',
      currentOilInventory: json['currentOilInventory'] as String? ?? '',
      expectedOilInventory: json['expectedOilInventory'] as String? ?? '',
      currentCushion: json['currentCushion'] as String? ?? '',
      maximumCushion: json['maximumCushion'] as String? ?? '',
    );
  }

  final String wellName;
  final String beginningOilInventory;
  final String currentOilInventory;
  final String expectedOilInventory;
  final String currentCushion;
  final String maximumCushion;

  ProductionOilInventoryWell copyWith({
    String? wellName,
    String? beginningOilInventory,
    String? currentOilInventory,
    String? expectedOilInventory,
    String? currentCushion,
    String? maximumCushion,
  }) {
    return ProductionOilInventoryWell(
      wellName: wellName ?? this.wellName,
      beginningOilInventory:
          beginningOilInventory ?? this.beginningOilInventory,
      currentOilInventory: currentOilInventory ?? this.currentOilInventory,
      expectedOilInventory: expectedOilInventory ?? this.expectedOilInventory,
      currentCushion: currentCushion ?? this.currentCushion,
      maximumCushion: maximumCushion ?? this.maximumCushion,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wellName': wellName,
      'beginningOilInventory': beginningOilInventory,
      'currentOilInventory': currentOilInventory,
      'expectedOilInventory': expectedOilInventory,
      'currentCushion': currentCushion,
      'maximumCushion': maximumCushion,
    };
  }
}

class ProductionTank {
  const ProductionTank({
    this.name = '',
    this.gauge = '',
    this.gaugeEntry = const ProductionGaugeEntry(),
    this.bblPerInch = '1.67',
  });

  factory ProductionTank.fromJson(Map<String, dynamic> json) {
    final gaugeEntryRaw = json['gaugeEntry'];
    final gaugeEntry = gaugeEntryRaw is Map
        ? ProductionGaugeEntry.fromJson(
            Map<String, dynamic>.from(gaugeEntryRaw),
          )
        : ProductionGaugeEntry.fromLegacyGauge(json['gauge'] as String? ?? '');
    final gauge = (json['gauge'] as String? ?? '').trim();
    return ProductionTank(
      name: json['name'] as String? ?? '',
      gauge: gauge.isEmpty ? gaugeEntry.inchesText() : gauge,
      gaugeEntry: gaugeEntry,
      bblPerInch: json['bblPerInch'] as String? ?? '1.67',
    );
  }

  final String name;
  final String gauge;
  final ProductionGaugeEntry gaugeEntry;
  final String bblPerInch;

  ProductionTank copyWith({
    String? name,
    String? gauge,
    ProductionGaugeEntry? gaugeEntry,
    String? bblPerInch,
  }) {
    final nextEntry = gaugeEntry ?? this.gaugeEntry;
    return ProductionTank(
      name: name ?? this.name,
      gauge: (gauge ?? this.gauge).trim().isEmpty
          ? nextEntry.inchesText()
          : gauge ?? this.gauge,
      gaugeEntry: nextEntry,
      bblPerInch: bblPerInch ?? this.bblPerInch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'gauge': gauge,
      'gaugeEntry': gaugeEntry.toJson(),
      'bblPerInch': bblPerInch,
    };
  }
}

class ProductionWellCheckData {
  static const List<String> supportedChemicals = <String>[
    'Biocide',
    'Scavenger',
    'Defoamer',
    'Scale Inhibitor',
  ];

  const ProductionWellCheckData({
    this.hoursSincePrevious = '',
    this.choke = '',
    this.chokeType = 'ADJ',
    this.tbg = '',
    this.icp = '',
    this.csg = '',
    this.currentGasAccum = '',
    this.salesGasRate = '',
    this.gasStatic = '',
    this.gasDifferential = '',
    this.gasTemp = '',
    this.waterSpecificGravity = '',
    this.wellheadTemp = '',
    this.waterTemp = '',
    this.flareRate = '',
    this.flarePilotTemp = '',
    this.biocide = '',
    this.scavenger = '',
    this.defoamer = '',
    this.scaleInhibitor = '',
    this.vruGasRate = '',
    this.compressorInjection = '',
    this.vruSuction = '',
    this.vruDischarge = '',
    this.waterTankGauges = const [],
    this.oilTankGauges = const [],
    this.waterTankGaugeEntries = const [],
    this.oilTankGaugeEntries = const [],
    this.waterHauled = '',
    this.oilHauled = '',
    this.waterPumped = '',
    this.oilPumped = '',
    this.sandRate = '',
    this.notes = '',
    this.beginningOilInventory = '',
    this.expectedOilInventory = '',
    this.maximumCushion = '',
  });

  factory ProductionWellCheckData.fromJson(Map<String, dynamic> json) {
    final waterGauges = ((json['waterTankGauges'] as List?) ?? const [])
        .map((item) => item?.toString() ?? '')
        .toList();
    final oilGauges = ((json['oilTankGauges'] as List?) ?? const [])
        .map((item) => item?.toString() ?? '')
        .toList();

    List<ProductionGaugeEntry> parseGaugeEntries(
      dynamic entries,
      List<String> fallback,
    ) {
      if (entries is List) {
        return entries
            .map((item) => item is Map
                ? ProductionGaugeEntry.fromJson(
                    Map<String, dynamic>.from(item),
                  )
                : const ProductionGaugeEntry())
            .toList();
      }
      return fallback
          .map((value) => ProductionGaugeEntry.fromLegacyGauge(value))
          .toList();
    }

    return ProductionWellCheckData(
      hoursSincePrevious: json['hoursSincePrevious'] as String? ?? '',
      choke: json['choke'] as String? ?? '',
      chokeType: ProductionShiftHeader._normalizeChokeType(
        json['chokeType'] as String?,
      ),
      tbg: json['tbg'] as String? ?? '',
      icp: json['icp'] as String? ?? '',
      csg: json['csg'] as String? ?? '',
      currentGasAccum: json['currentGasAccum'] as String? ?? '',
      salesGasRate: json['salesGasRate'] as String? ?? '',
      gasStatic: json['gasStatic'] as String? ?? '',
      gasDifferential: json['gasDifferential'] as String? ?? '',
      gasTemp: json['gasTemp'] as String? ?? '',
      waterSpecificGravity: json['waterSpecificGravity'] as String? ?? '',
      wellheadTemp: json['wellheadTemp'] as String? ?? '',
      waterTemp: json['waterTemp'] as String? ?? '',
      flareRate: json['flareRate'] as String? ?? '',
      flarePilotTemp: json['flarePilotTemp'] as String? ?? '',
      biocide: json['biocide'] as String? ?? '',
      scavenger: json['scavenger'] as String? ?? '',
      defoamer: json['defoamer'] as String? ?? '',
      scaleInhibitor: json['scaleInhibitor'] as String? ?? '',
      vruGasRate: json['vruGasRate'] as String? ?? '',
      compressorInjection: json['compressorInjection'] as String? ?? '',
      vruSuction: json['vruSuction'] as String? ?? '',
      vruDischarge: json['vruDischarge'] as String? ?? '',
      waterTankGauges: waterGauges,
      oilTankGauges: oilGauges,
      waterTankGaugeEntries:
          parseGaugeEntries(json['waterTankGaugeEntries'], waterGauges),
      oilTankGaugeEntries:
          parseGaugeEntries(json['oilTankGaugeEntries'], oilGauges),
      waterHauled: json['waterHauled'] as String? ?? '',
      oilHauled: json['oilHauled'] as String? ?? '',
      waterPumped: json['waterPumped'] as String? ?? '',
      oilPumped: json['oilPumped'] as String? ?? '',
      sandRate: json['sandRate'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      beginningOilInventory: json['beginningOilInventory'] as String? ?? '',
      expectedOilInventory: json['expectedOilInventory'] as String? ?? '',
      maximumCushion: json['maximumCushion'] as String? ?? '',
    );
  }

  factory ProductionWellCheckData.fromHourlyCheck(ProductionHourlyCheck check) {
    return ProductionWellCheckData(
      hoursSincePrevious: check.hoursSincePrevious,
      choke: check.choke,
      chokeType: check.chokeType,
      tbg: check.tbg,
      icp: check.icp,
      csg: check.csg,
      currentGasAccum: check.currentGasAccum,
      salesGasRate: check.salesGasRate,
      gasStatic: check.gasStatic,
      gasDifferential: check.gasDifferential,
      gasTemp: check.gasTemp,
      waterSpecificGravity: check.waterSpecificGravity,
      wellheadTemp: check.wellheadTemp,
      waterTemp: check.waterTemp,
      flareRate: check.flareRate,
      flarePilotTemp: check.flarePilotTemp,
      biocide: check.biocide,
      scavenger: check.scavenger,
      defoamer: check.defoamer,
      scaleInhibitor: check.scaleInhibitor,
      vruGasRate: check.vruGasRate,
      compressorInjection: check.compressorInjection,
      vruSuction: check.vruSuction,
      vruDischarge: check.vruDischarge,
      waterTankGauges: check.waterTankGauges,
      oilTankGauges: check.oilTankGauges,
      waterTankGaugeEntries: check.waterTankGaugeEntries,
      oilTankGaugeEntries: check.oilTankGaugeEntries,
      waterHauled: check.waterHauled,
      oilHauled: check.oilHauled,
      waterPumped: check.waterPumped,
      oilPumped: check.oilPumped,
      sandRate: check.sandRate,
      notes: check.notes,
      beginningOilInventory: '',
      expectedOilInventory: '',
      maximumCushion: '',
    );
  }

  final String hoursSincePrevious;
  final String choke;
  final String chokeType;
  final String tbg;
  final String icp;
  final String csg;
  final String currentGasAccum;
  final String salesGasRate;
  final String gasStatic;
  final String gasDifferential;
  final String gasTemp;
  final String waterSpecificGravity;
  final String wellheadTemp;
  final String waterTemp;
  final String flareRate;
  final String flarePilotTemp;
  final String biocide;
  final String scavenger;
  final String defoamer;
  final String scaleInhibitor;
  final String vruGasRate;
  final String compressorInjection;
  final String vruSuction;
  final String vruDischarge;
  final List<String> waterTankGauges;
  final List<String> oilTankGauges;
  final List<ProductionGaugeEntry> waterTankGaugeEntries;
  final List<ProductionGaugeEntry> oilTankGaugeEntries;
  final String waterHauled;
  final String oilHauled;
  final String waterPumped;
  final String oilPumped;
  final String sandRate;
  final String notes;
  final String beginningOilInventory;
  final String expectedOilInventory;
  final String maximumCushion;

  Map<String, dynamic> toJson() {
    return {
      'hoursSincePrevious': hoursSincePrevious,
      'choke': choke,
      'chokeType': chokeType,
      'tbg': tbg,
      'icp': icp,
      'csg': csg,
      'currentGasAccum': currentGasAccum,
      'salesGasRate': salesGasRate,
      'gasStatic': gasStatic,
      'gasDifferential': gasDifferential,
      'gasTemp': gasTemp,
      'waterSpecificGravity': waterSpecificGravity,
      'wellheadTemp': wellheadTemp,
      'waterTemp': waterTemp,
      'flareRate': flareRate,
      'flarePilotTemp': flarePilotTemp,
      'biocide': biocide,
      'scavenger': scavenger,
      'defoamer': defoamer,
      'scaleInhibitor': scaleInhibitor,
      'vruGasRate': vruGasRate,
      'compressorInjection': compressorInjection,
      'vruSuction': vruSuction,
      'vruDischarge': vruDischarge,
      'waterTankGauges': waterTankGauges,
      'oilTankGauges': oilTankGauges,
      'waterTankGaugeEntries':
          waterTankGaugeEntries.map((item) => item.toJson()).toList(),
      'oilTankGaugeEntries':
          oilTankGaugeEntries.map((item) => item.toJson()).toList(),
      'waterHauled': waterHauled,
      'oilHauled': oilHauled,
      'waterPumped': waterPumped,
      'oilPumped': oilPumped,
      'sandRate': sandRate,
      'notes': notes,
      'beginningOilInventory': beginningOilInventory,
      'expectedOilInventory': expectedOilInventory,
      'maximumCushion': maximumCushion,
    };
  }
}

class ProductionHourlyCheck {
  const ProductionHourlyCheck({
    required this.time,
    this.well = '',
    this.wellChecks = const {},
    this.hoursSincePrevious = '',
    this.choke = '',
    this.chokeType = 'ADJ',
    this.tbg = '',
    this.icp = '',
    this.csg = '',
    this.currentGasAccum = '',
    this.salesGasRate = '',
    this.gasStatic = '',
    this.gasDifferential = '',
    this.gasTemp = '',
    this.waterSpecificGravity = '',
    this.wellheadTemp = '',
    this.waterTemp = '',
    this.flareRate = '',
    this.flarePilotTemp = '',
    this.biocide = '',
    this.scavenger = '',
    this.defoamer = '',
    this.scaleInhibitor = '',
    this.vruGasRate = '',
    this.compressorInjection = '',
    this.vruSuction = '',
    this.vruDischarge = '',
    this.waterTankGauges = const [],
    this.oilTankGauges = const [],
    this.waterTankGaugeEntries = const [],
    this.oilTankGaugeEntries = const [],
    this.waterHauled = '',
    this.oilHauled = '',
    this.waterPumped = '',
    this.oilPumped = '',
    this.sandRate = '',
    this.notes = '',
  });

  factory ProductionHourlyCheck.fromJson(Map<String, dynamic> json) {
    final waterGauges = ((json['waterTankGauges'] as List?) ?? const [])
        .map((item) => item?.toString() ?? '')
        .toList();
    final oilGauges = ((json['oilTankGauges'] as List?) ?? const [])
        .map((item) => item?.toString() ?? '')
        .toList();

    List<ProductionGaugeEntry> parseGaugeEntries(
      dynamic entries,
      List<String> fallback,
    ) {
      if (entries is List) {
        return entries
            .map((item) => item is Map
                ? ProductionGaugeEntry.fromJson(
                    Map<String, dynamic>.from(item),
                  )
                : const ProductionGaugeEntry())
            .toList();
      }
      return fallback
          .map((value) => ProductionGaugeEntry.fromLegacyGauge(value))
          .toList();
    }

    return ProductionHourlyCheck(
      time: json['time'] as String? ?? '',
      well: json['well'] as String? ?? '',
      wellChecks: ((json['wellChecks'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          value is Map
              ? ProductionWellCheckData.fromJson(
                  Map<String, dynamic>.from(value),
                )
              : const ProductionWellCheckData(),
        ),
      ),
      hoursSincePrevious: json['hoursSincePrevious'] as String? ?? '',
      choke: json['choke'] as String? ?? '',
      chokeType: ProductionShiftHeader._normalizeChokeType(
        json['chokeType'] as String?,
      ),
      tbg: json['tbg'] as String? ?? '',
      icp: json['icp'] as String? ?? '',
      csg: json['csg'] as String? ?? '',
      currentGasAccum: json['currentGasAccum'] as String? ?? '',
      salesGasRate: json['salesGasRate'] as String? ?? '',
      gasStatic: json['gasStatic'] as String? ?? '',
      gasDifferential: json['gasDifferential'] as String? ?? '',
      gasTemp: json['gasTemp'] as String? ?? '',
      waterSpecificGravity: json['waterSpecificGravity'] as String? ?? '',
      wellheadTemp: json['wellheadTemp'] as String? ?? '',
      waterTemp: json['waterTemp'] as String? ?? '',
      flareRate: json['flareRate'] as String? ?? '',
      flarePilotTemp: json['flarePilotTemp'] as String? ?? '',
      biocide: json['biocide'] as String? ?? '',
      scavenger: json['scavenger'] as String? ?? '',
      defoamer: json['defoamer'] as String? ?? '',
      scaleInhibitor: json['scaleInhibitor'] as String? ?? '',
      vruGasRate: json['vruGasRate'] as String? ?? '',
      compressorInjection: json['compressorInjection'] as String? ?? '',
      vruSuction: json['vruSuction'] as String? ?? '',
      vruDischarge: json['vruDischarge'] as String? ?? '',
      waterTankGauges: waterGauges,
      oilTankGauges: oilGauges,
      waterTankGaugeEntries:
          parseGaugeEntries(json['waterTankGaugeEntries'], waterGauges),
      oilTankGaugeEntries:
          parseGaugeEntries(json['oilTankGaugeEntries'], oilGauges),
      waterHauled: json['waterHauled'] as String? ?? '',
      oilHauled: json['oilHauled'] as String? ?? '',
      waterPumped: json['waterPumped'] as String? ?? '',
      oilPumped: json['oilPumped'] as String? ?? '',
      sandRate: json['sandRate'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }

  final String time;
  final String well;
  final Map<String, ProductionWellCheckData> wellChecks;
  final String hoursSincePrevious;
  final String choke;
  final String chokeType;
  final String tbg;
  final String icp;
  final String csg;
  final String currentGasAccum;
  final String salesGasRate;
  final String gasStatic;
  final String gasDifferential;
  final String gasTemp;
  final String waterSpecificGravity;
  final String wellheadTemp;
  final String waterTemp;
  final String flareRate;
  final String flarePilotTemp;
  final String biocide;
  final String scavenger;
  final String defoamer;
  final String scaleInhibitor;
  final String vruGasRate;
  final String compressorInjection;
  final String vruSuction;
  final String vruDischarge;
  final List<String> waterTankGauges;
  final List<String> oilTankGauges;
  final List<ProductionGaugeEntry> waterTankGaugeEntries;
  final List<ProductionGaugeEntry> oilTankGaugeEntries;
  final String waterHauled;
  final String oilHauled;
  final String waterPumped;
  final String oilPumped;
  final String sandRate;
  final String notes;

  ProductionHourlyCheck copyWith({
    String? time,
    String? well,
    Map<String, ProductionWellCheckData>? wellChecks,
    String? hoursSincePrevious,
    String? choke,
    String? chokeType,
    String? tbg,
    String? icp,
    String? csg,
    String? currentGasAccum,
    String? salesGasRate,
    String? gasStatic,
    String? gasDifferential,
    String? gasTemp,
    String? waterSpecificGravity,
    String? wellheadTemp,
    String? waterTemp,
    String? flareRate,
    String? flarePilotTemp,
    String? biocide,
    String? scavenger,
    String? defoamer,
    String? scaleInhibitor,
    String? vruGasRate,
    String? compressorInjection,
    String? vruSuction,
    String? vruDischarge,
    List<String>? waterTankGauges,
    List<String>? oilTankGauges,
    List<ProductionGaugeEntry>? waterTankGaugeEntries,
    List<ProductionGaugeEntry>? oilTankGaugeEntries,
    String? waterHauled,
    String? oilHauled,
    String? waterPumped,
    String? oilPumped,
    String? sandRate,
    String? notes,
  }) {
    return ProductionHourlyCheck(
      time: time ?? this.time,
      well: well ?? this.well,
      wellChecks: wellChecks ?? this.wellChecks,
      hoursSincePrevious: hoursSincePrevious ?? this.hoursSincePrevious,
      choke: choke ?? this.choke,
      chokeType: ProductionShiftHeader._normalizeChokeType(
        chokeType ?? this.chokeType,
      ),
      tbg: tbg ?? this.tbg,
      icp: icp ?? this.icp,
      csg: csg ?? this.csg,
      currentGasAccum: currentGasAccum ?? this.currentGasAccum,
      salesGasRate: salesGasRate ?? this.salesGasRate,
      gasStatic: gasStatic ?? this.gasStatic,
      gasDifferential: gasDifferential ?? this.gasDifferential,
      gasTemp: gasTemp ?? this.gasTemp,
      waterSpecificGravity: waterSpecificGravity ?? this.waterSpecificGravity,
      wellheadTemp: wellheadTemp ?? this.wellheadTemp,
      waterTemp: waterTemp ?? this.waterTemp,
      flareRate: flareRate ?? this.flareRate,
      flarePilotTemp: flarePilotTemp ?? this.flarePilotTemp,
      biocide: biocide ?? this.biocide,
      scavenger: scavenger ?? this.scavenger,
      defoamer: defoamer ?? this.defoamer,
      scaleInhibitor: scaleInhibitor ?? this.scaleInhibitor,
      vruGasRate: vruGasRate ?? this.vruGasRate,
      compressorInjection: compressorInjection ?? this.compressorInjection,
      vruSuction: vruSuction ?? this.vruSuction,
      vruDischarge: vruDischarge ?? this.vruDischarge,
      waterTankGauges: waterTankGauges ?? this.waterTankGauges,
      oilTankGauges: oilTankGauges ?? this.oilTankGauges,
      waterTankGaugeEntries:
          waterTankGaugeEntries ?? this.waterTankGaugeEntries,
      oilTankGaugeEntries: oilTankGaugeEntries ?? this.oilTankGaugeEntries,
      waterHauled: waterHauled ?? this.waterHauled,
      oilHauled: oilHauled ?? this.oilHauled,
      waterPumped: waterPumped ?? this.waterPumped,
      oilPumped: oilPumped ?? this.oilPumped,
      sandRate: sandRate ?? this.sandRate,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'time': time,
      'well': well,
      'wellChecks': wellChecks.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'hoursSincePrevious': hoursSincePrevious,
      'choke': choke,
      'chokeType': chokeType,
      'tbg': tbg,
      'icp': icp,
      'csg': csg,
      'currentGasAccum': currentGasAccum,
      'salesGasRate': salesGasRate,
      'gasStatic': gasStatic,
      'gasDifferential': gasDifferential,
      'gasTemp': gasTemp,
      'waterSpecificGravity': waterSpecificGravity,
      'wellheadTemp': wellheadTemp,
      'waterTemp': waterTemp,
      'flareRate': flareRate,
      'flarePilotTemp': flarePilotTemp,
      'biocide': biocide,
      'scavenger': scavenger,
      'defoamer': defoamer,
      'scaleInhibitor': scaleInhibitor,
      'vruGasRate': vruGasRate,
      'compressorInjection': compressorInjection,
      'vruSuction': vruSuction,
      'vruDischarge': vruDischarge,
      'waterTankGauges': waterTankGauges,
      'oilTankGauges': oilTankGauges,
      'waterTankGaugeEntries':
          waterTankGaugeEntries.map((item) => item.toJson()).toList(),
      'oilTankGaugeEntries':
          oilTankGaugeEntries.map((item) => item.toJson()).toList(),
      'waterHauled': waterHauled,
      'oilHauled': oilHauled,
      'waterPumped': waterPumped,
      'oilPumped': oilPumped,
      'sandRate': sandRate,
      'notes': notes,
    };
  }
}

class ProductionReportRow {
  const ProductionReportRow({
    required this.hourIndex,
    required this.time,
    required this.well,
    required this.choke,
    this.chokeType = 'ADJ',
    required this.tbg,
    this.icp = '',
    required this.csg,
    required this.waterProduction,
    required this.oilProduction,
    required this.hourlyGas,
    required this.gas24HourRate,
    this.salesGasRate = 0,
    required this.gasStatic,
    required this.gasDifferential,
    required this.gasTemp,
    this.waterSpecificGravity = '',
    this.wellheadTemp = '',
    this.waterTemp = '',
    this.flareRate = '',
    this.flarePilotTemp = '',
    this.biocide = '',
    this.scavenger = '',
    this.defoamer = '',
    this.scaleInhibitor = '',
    this.vruGasRate = '',
    this.compressorInjection = '',
    this.vruSuction = '',
    this.vruDischarge = '',
    required this.sandRate,
    required this.waterGaugeText,
    required this.oilGaugeText,
    required this.currentWaterBbl,
    required this.currentOilBbl,
    required this.currentGasAccum,
    this.hoursSincePrevious = 0,
    required this.waterHauled,
    required this.oilHauled,
    required this.waterPumped,
    required this.oilPumped,
    required this.notes,
  });

  factory ProductionReportRow.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return ProductionReportRow(
      hourIndex: json['hourIndex'] as int? ?? 0,
      time: json['time'] as String? ?? '',
      well: json['well'] as String? ?? '',
      choke: json['choke'] as String? ?? '',
      chokeType: ProductionShiftHeader._normalizeChokeType(
        json['chokeType'] as String?,
      ),
      tbg: json['tbg'] as String? ?? '',
      icp: json['icp'] as String? ?? '',
      csg: json['csg'] as String? ?? '',
      waterProduction: asDouble(json['waterProduction']),
      oilProduction: asDouble(json['oilProduction']),
      hourlyGas: asDouble(json['hourlyGas']),
      gas24HourRate: asDouble(json['gas24HourRate']),
      salesGasRate: asDouble(json['salesGasRate']),
      gasStatic: json['gasStatic'] as String? ?? '',
      gasDifferential: json['gasDifferential'] as String? ?? '',
      gasTemp: json['gasTemp'] as String? ?? '',
      waterSpecificGravity: json['waterSpecificGravity'] as String? ?? '',
      wellheadTemp: json['wellheadTemp'] as String? ?? '',
      waterTemp: json['waterTemp'] as String? ?? '',
      flareRate: json['flareRate'] as String? ?? '',
      flarePilotTemp: json['flarePilotTemp'] as String? ?? '',
      biocide: json['biocide'] as String? ?? '',
      scavenger: json['scavenger'] as String? ?? '',
      defoamer: json['defoamer'] as String? ?? '',
      scaleInhibitor: json['scaleInhibitor'] as String? ?? '',
      vruGasRate: json['vruGasRate'] as String? ?? '',
      compressorInjection: json['compressorInjection'] as String? ?? '',
      vruSuction: json['vruSuction'] as String? ?? '',
      vruDischarge: json['vruDischarge'] as String? ?? '',
      sandRate: json['sandRate'] as String? ?? '',
      waterGaugeText: json['waterGaugeText'] as String? ?? '',
      oilGaugeText: json['oilGaugeText'] as String? ?? '',
      currentWaterBbl: asDouble(json['currentWaterBbl']),
      currentOilBbl: asDouble(json['currentOilBbl']),
      currentGasAccum: asDouble(json['currentGasAccum']),
      hoursSincePrevious: asDouble(json['hoursSincePrevious']),
      waterHauled: asDouble(json['waterHauled']),
      oilHauled: asDouble(json['oilHauled']),
      waterPumped: asDouble(json['waterPumped']),
      oilPumped: asDouble(json['oilPumped']),
      notes: json['notes'] as String? ?? '',
    );
  }

  final int hourIndex;
  final String time;
  final String well;
  final String choke;
  final String chokeType;
  final String tbg;
  final String icp;
  final String csg;
  final double waterProduction;
  final double oilProduction;
  final double hourlyGas;
  final double gas24HourRate;
  final double salesGasRate;
  final String gasStatic;
  final String gasDifferential;
  final String gasTemp;
  final String waterSpecificGravity;
  final String wellheadTemp;
  final String waterTemp;
  final String flareRate;
  final String flarePilotTemp;
  final String biocide;
  final String scavenger;
  final String defoamer;
  final String scaleInhibitor;
  final String vruGasRate;
  final String compressorInjection;
  final String vruSuction;
  final String vruDischarge;
  final String sandRate;
  final String waterGaugeText;
  final String oilGaugeText;
  final double currentWaterBbl;
  final double currentOilBbl;
  final double currentGasAccum;
  final double hoursSincePrevious;
  final double waterHauled;
  final double oilHauled;
  final double waterPumped;
  final double oilPumped;
  final String notes;

  Map<String, dynamic> toJson() {
    return {
      'hourIndex': hourIndex,
      'time': time,
      'well': well,
      'choke': choke,
      'chokeType': chokeType,
      'tbg': tbg,
      'icp': icp,
      'csg': csg,
      'waterProduction': waterProduction,
      'oilProduction': oilProduction,
      'hourlyGas': hourlyGas,
      'gas24HourRate': gas24HourRate,
      'salesGasRate': salesGasRate,
      'gasStatic': gasStatic,
      'gasDifferential': gasDifferential,
      'gasTemp': gasTemp,
      'waterSpecificGravity': waterSpecificGravity,
      'wellheadTemp': wellheadTemp,
      'waterTemp': waterTemp,
      'flareRate': flareRate,
      'flarePilotTemp': flarePilotTemp,
      'biocide': biocide,
      'scavenger': scavenger,
      'defoamer': defoamer,
      'scaleInhibitor': scaleInhibitor,
      'vruGasRate': vruGasRate,
      'compressorInjection': compressorInjection,
      'vruSuction': vruSuction,
      'vruDischarge': vruDischarge,
      'sandRate': sandRate,
      'waterGaugeText': waterGaugeText,
      'oilGaugeText': oilGaugeText,
      'currentWaterBbl': currentWaterBbl,
      'currentOilBbl': currentOilBbl,
      'currentGasAccum': currentGasAccum,
      'hoursSincePrevious': hoursSincePrevious,
      'waterHauled': waterHauled,
      'oilHauled': oilHauled,
      'waterPumped': waterPumped,
      'oilPumped': oilPumped,
      'notes': notes,
    };
  }
}
