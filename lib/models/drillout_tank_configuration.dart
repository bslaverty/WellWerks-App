class DrilloutTankRole {
  const DrilloutTankRole({
    required this.id,
    required this.label,
    required this.allowedTypeIds,
  });

  final String id;
  final String label;
  final List<String> allowedTypeIds;
}

class DrilloutTankType {
  const DrilloutTankType({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class DrilloutTankSelection {
  const DrilloutTankSelection({
    required this.roleId,
    required this.typeId,
    this.gauge = '',
  });

  final String roleId;
  final String typeId;
  final String gauge;

  DrilloutTankSelection copyWith({
    String? roleId,
    String? typeId,
    String? gauge,
  }) {
    return DrilloutTankSelection(
      roleId: roleId ?? this.roleId,
      typeId: typeId ?? this.typeId,
      gauge: gauge ?? this.gauge,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'roleId': roleId,
        'typeId': typeId,
        'gauge': gauge,
      };

  factory DrilloutTankSelection.fromJson(Map<String, dynamic> json) {
    return DrilloutTankSelection(
      roleId: (json['roleId'] as String? ?? '').trim(),
      typeId: (json['typeId'] as String? ?? '').trim(),
      gauge: (json['gauge'] as String? ?? '').trim(),
    );
  }
}

class DrilloutTankCatalog {
  static const String typeFs3 = 'fs3';
  static const String typeSandX = 'sandx';
  static const String typeFlowbackRoundBottom = 'flowback_round_bottom';
  static const String typeFlowbackVBottom = 'flowback_v_bottom';

  static const String roleSandTank = 'sand_tank';
  static const String roleFlowback1 = 'flowback_tank_1';
  static const String roleFlowback2 = 'flowback_tank_2';
  static const String roleFlowback3 = 'flowback_tank_3';
  static const String roleSweep1 = 'sweep_tank_1';
  static const String roleSweep2 = 'sweep_tank_2';
  static const String roleSweep3 = 'sweep_tank_3';

  static const List<DrilloutTankType> tankTypes = <DrilloutTankType>[
    DrilloutTankType(id: typeFs3, label: 'FS3'),
    DrilloutTankType(id: typeSandX, label: 'SandX'),
    DrilloutTankType(
      id: typeFlowbackRoundBottom,
      label: 'Flowback Tank - Round Bottom',
    ),
    DrilloutTankType(
      id: typeFlowbackVBottom,
      label: 'Flowback Tank - V Bottom',
    ),
  ];

  static const List<DrilloutTankRole> roles = <DrilloutTankRole>[
    DrilloutTankRole(
      id: roleSandTank,
      label: 'Sand Tank',
      allowedTypeIds: <String>[
        typeFs3,
        typeSandX,
        typeFlowbackRoundBottom,
        typeFlowbackVBottom,
      ],
    ),
    DrilloutTankRole(
      id: roleFlowback1,
      label: 'Flowback Tank 1',
      allowedTypeIds: <String>[typeFlowbackRoundBottom, typeFlowbackVBottom],
    ),
    DrilloutTankRole(
      id: roleFlowback2,
      label: 'Flowback Tank 2',
      allowedTypeIds: <String>[typeFlowbackRoundBottom, typeFlowbackVBottom],
    ),
    DrilloutTankRole(
      id: roleFlowback3,
      label: 'Flowback Tank 3',
      allowedTypeIds: <String>[typeFlowbackRoundBottom, typeFlowbackVBottom],
    ),
    DrilloutTankRole(
      id: roleSweep1,
      label: 'Sweep Tank 1',
      allowedTypeIds: <String>[typeFlowbackRoundBottom, typeFlowbackVBottom],
    ),
    DrilloutTankRole(
      id: roleSweep2,
      label: 'Sweep Tank 2',
      allowedTypeIds: <String>[typeFlowbackRoundBottom, typeFlowbackVBottom],
    ),
    DrilloutTankRole(
      id: roleSweep3,
      label: 'Sweep Tank 3',
      allowedTypeIds: <String>[typeFlowbackRoundBottom, typeFlowbackVBottom],
    ),
  ];

  static const List<String> flowbackRoleIds = <String>[
    roleFlowback1,
    roleFlowback2,
    roleFlowback3,
  ];

  static const List<String> sweepRoleIds = <String>[
    roleSweep1,
    roleSweep2,
    roleSweep3,
  ];

  static DrilloutTankRole roleById(String roleId) {
    return roles.firstWhere(
      (role) => role.id == roleId,
      orElse: () => roles.first,
    );
  }

  static DrilloutTankType typeById(String typeId) {
    return tankTypes.firstWhere(
      (type) => type.id == typeId,
      orElse: () => tankTypes.first,
    );
  }

  static String normalizeTypeForRole(String roleId, String typeId) {
    final role = roleById(roleId);
    if (role.allowedTypeIds.contains(typeId)) {
      return typeId;
    }
    return role.allowedTypeIds.first;
  }

  static String normalizeLegacyType(String raw) {
    switch ((raw).trim()) {
      case 'fs3':
        return typeFs3;
      case 'sandx':
      case 'sand_tank':
        return typeSandX;
      case 'flowback500':
      case typeFlowbackVBottom:
        return typeFlowbackVBottom;
      case typeFlowbackRoundBottom:
      default:
        return typeFlowbackRoundBottom;
    }
  }
}

class DrilloutTankConfiguration {
  const DrilloutTankConfiguration({
    required this.sandTankType,
    required this.flowbackTankTypes,
    required this.sweepTankTypes,
    this.gaugesByRole = const <String, String>{},
    this.migratedFromLegacy = false,
  });

  final String sandTankType;
  final List<String> flowbackTankTypes;
  final List<String> sweepTankTypes;
  final Map<String, String> gaugesByRole;
  final bool migratedFromLegacy;

  static const DrilloutTankConfiguration defaults = DrilloutTankConfiguration(
    sandTankType: DrilloutTankCatalog.typeSandX,
    flowbackTankTypes: <String>[],
    sweepTankTypes: <String>[],
  );

  int get flowbackCount => flowbackTankTypes.length.clamp(0, 3);
  int get sweepCount => sweepTankTypes.length.clamp(0, 3);

  List<DrilloutTankSelection> get activeSelections {
    final selections = <DrilloutTankSelection>[];
    selections.add(
      DrilloutTankSelection(
        roleId: DrilloutTankCatalog.roleSandTank,
        typeId: DrilloutTankCatalog.normalizeTypeForRole(
          DrilloutTankCatalog.roleSandTank,
          sandTankType,
        ),
        gauge: gaugesByRole[DrilloutTankCatalog.roleSandTank] ?? '',
      ),
    );

    for (var i = 0;
        i < flowbackCount && i < DrilloutTankCatalog.flowbackRoleIds.length;
        i++) {
      final roleId = DrilloutTankCatalog.flowbackRoleIds[i];
      selections.add(
        DrilloutTankSelection(
          roleId: roleId,
          typeId: DrilloutTankCatalog.normalizeTypeForRole(
            roleId,
            flowbackTankTypes[i],
          ),
          gauge: gaugesByRole[roleId] ?? '',
        ),
      );
    }

    for (var i = 0;
        i < sweepCount && i < DrilloutTankCatalog.sweepRoleIds.length;
        i++) {
      final roleId = DrilloutTankCatalog.sweepRoleIds[i];
      selections.add(
        DrilloutTankSelection(
          roleId: roleId,
          typeId: DrilloutTankCatalog.normalizeTypeForRole(
            roleId,
            sweepTankTypes[i],
          ),
          gauge: gaugesByRole[roleId] ?? '',
        ),
      );
    }

    return selections;
  }

  DrilloutTankConfiguration copyWith({
    String? sandTankType,
    List<String>? flowbackTankTypes,
    List<String>? sweepTankTypes,
    Map<String, String>? gaugesByRole,
    bool? migratedFromLegacy,
  }) {
    return DrilloutTankConfiguration(
      sandTankType: DrilloutTankCatalog.normalizeTypeForRole(
        DrilloutTankCatalog.roleSandTank,
        sandTankType ?? this.sandTankType,
      ),
      flowbackTankTypes: _normalizeTypeList(
        DrilloutTankCatalog.flowbackRoleIds,
        flowbackTankTypes ?? this.flowbackTankTypes,
      ),
      sweepTankTypes: _normalizeTypeList(
        DrilloutTankCatalog.sweepRoleIds,
        sweepTankTypes ?? this.sweepTankTypes,
      ),
      gaugesByRole: gaugesByRole ?? this.gaugesByRole,
      migratedFromLegacy: migratedFromLegacy ?? this.migratedFromLegacy,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sandTankType': DrilloutTankCatalog.normalizeTypeForRole(
        DrilloutTankCatalog.roleSandTank,
        sandTankType,
      ),
      'flowbackTankTypes': _normalizeTypeList(
        DrilloutTankCatalog.flowbackRoleIds,
        flowbackTankTypes,
      ),
      'sweepTankTypes': _normalizeTypeList(
        DrilloutTankCatalog.sweepRoleIds,
        sweepTankTypes,
      ),
      'gaugesByRole': gaugesByRole,
    };
  }

  Map<String, dynamic> toLegacyCompatJson() {
    final compat = <String, dynamic>{
      'showFlowbackTank': true,
      'flowbackTankType': DrilloutTankCatalog.normalizeTypeForRole(
        DrilloutTankCatalog.roleSandTank,
        sandTankType,
      ),
      'showWaterTank1': flowbackCount >= 1,
      'showWaterTank2': flowbackCount >= 2,
      'showSweepTank': sweepCount >= 1,
      'waterTank1Type': flowbackCount >= 1
          ? DrilloutTankCatalog.normalizeTypeForRole(
              DrilloutTankCatalog.roleFlowback1,
              flowbackTankTypes[0],
            )
          : DrilloutTankCatalog.typeFlowbackRoundBottom,
      'waterTank2Type': flowbackCount >= 2
          ? DrilloutTankCatalog.normalizeTypeForRole(
              DrilloutTankCatalog.roleFlowback2,
              flowbackTankTypes[1],
            )
          : DrilloutTankCatalog.typeFlowbackRoundBottom,
      'flowbackGauge': gaugesByRole[DrilloutTankCatalog.roleSandTank] ?? '',
      'waterTank1Gauge': gaugesByRole[DrilloutTankCatalog.roleFlowback1] ?? '',
      'waterTank2Gauge': gaugesByRole[DrilloutTankCatalog.roleFlowback2] ?? '',
      'sweepTankGauge': gaugesByRole[DrilloutTankCatalog.roleSweep1] ?? '',
    };
    return compat;
  }

  factory DrilloutTankConfiguration.fromJson(Map<String, dynamic> json) {
    final rawGauges = json['gaugesByRole'];
    final gaugesByRole = <String, String>{};
    if (rawGauges is Map) {
      for (final entry in rawGauges.entries) {
        gaugesByRole[entry.key.toString()] = (entry.value ?? '').toString();
      }
    }

    return DrilloutTankConfiguration(
      sandTankType: DrilloutTankCatalog.normalizeTypeForRole(
        DrilloutTankCatalog.roleSandTank,
        DrilloutTankCatalog.normalizeLegacyType(
          (json['sandTankType'] as String?) ?? DrilloutTankCatalog.typeSandX,
        ),
      ),
      flowbackTankTypes: _normalizeTypeList(
        DrilloutTankCatalog.flowbackRoleIds,
        (json['flowbackTankTypes'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => DrilloutTankCatalog.normalizeLegacyType(
                (item ?? '').toString()))
            .toList(),
      ),
      sweepTankTypes: _normalizeTypeList(
        DrilloutTankCatalog.sweepRoleIds,
        (json['sweepTankTypes'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => DrilloutTankCatalog.normalizeLegacyType(
                (item ?? '').toString()))
            .toList(),
      ),
      gaugesByRole: gaugesByRole,
    );
  }

  factory DrilloutTankConfiguration.fromDrilloutSetup(
    Map<String, dynamic> drilloutSetup,
  ) {
    final configRaw = drilloutSetup['tankConfigurationV1'];
    if (configRaw is Map) {
      return DrilloutTankConfiguration.fromJson(
        Map<String, dynamic>.from(configRaw),
      );
    }

    final legacyPrimary = DrilloutTankCatalog.normalizeLegacyType(
      (drilloutSetup['flowbackTankType'] as String?) ??
          (drilloutSetup['primaryTank'] as String?) ??
          DrilloutTankCatalog.typeSandX,
    );

    final flowback = <String>[];
    final showFlowback1 = drilloutSetup['showWaterTank1'] == true ||
        drilloutSetup['showWaterTank'] == true;
    if (showFlowback1) {
      flowback.add(
        DrilloutTankCatalog.normalizeTypeForRole(
          DrilloutTankCatalog.roleFlowback1,
          DrilloutTankCatalog.normalizeLegacyType(
            (drilloutSetup['waterTank1Type'] as String?) ??
                (drilloutSetup['waterTankType'] as String?) ??
                DrilloutTankCatalog.typeFlowbackRoundBottom,
          ),
        ),
      );
    }
    if (drilloutSetup['showWaterTank2'] == true) {
      flowback.add(
        DrilloutTankCatalog.normalizeTypeForRole(
          DrilloutTankCatalog.roleFlowback2,
          DrilloutTankCatalog.normalizeLegacyType(
            (drilloutSetup['waterTank2Type'] as String?) ??
                DrilloutTankCatalog.typeFlowbackRoundBottom,
          ),
        ),
      );
    }

    final sweep = <String>[];
    if (drilloutSetup['showSweepTank'] == true) {
      sweep.add(
        DrilloutTankCatalog.normalizeTypeForRole(
          DrilloutTankCatalog.roleSweep1,
          DrilloutTankCatalog.normalizeLegacyType(
            (drilloutSetup['sweepTankType'] as String?) ??
                DrilloutTankCatalog.typeFlowbackRoundBottom,
          ),
        ),
      );
    }

    final gaugesByRole = <String, String>{
      DrilloutTankCatalog.roleSandTank:
          (drilloutSetup['flowbackGauge'] as String? ?? '').trim(),
      DrilloutTankCatalog.roleFlowback1:
          (drilloutSetup['waterTank1Gauge'] as String? ?? '').trim(),
      DrilloutTankCatalog.roleFlowback2:
          (drilloutSetup['waterTank2Gauge'] as String? ?? '').trim(),
      DrilloutTankCatalog.roleSweep1:
          (drilloutSetup['sweepTankGauge'] as String? ?? '').trim(),
    };

    return DrilloutTankConfiguration(
      sandTankType: DrilloutTankCatalog.normalizeTypeForRole(
        DrilloutTankCatalog.roleSandTank,
        legacyPrimary,
      ),
      flowbackTankTypes: _normalizeTypeList(
        DrilloutTankCatalog.flowbackRoleIds,
        flowback,
      ),
      sweepTankTypes: _normalizeTypeList(
        DrilloutTankCatalog.sweepRoleIds,
        sweep,
      ),
      gaugesByRole: gaugesByRole,
      migratedFromLegacy: true,
    );
  }

  static List<String> _normalizeTypeList(
    List<String> roleIds,
    List<String> raw,
  ) {
    final out = <String>[];
    final max = raw.length > 3 ? 3 : raw.length;
    for (int i = 0; i < max && i < roleIds.length; i++) {
      out.add(DrilloutTankCatalog.normalizeTypeForRole(roleIds[i], raw[i]));
    }
    return out;
  }
}
