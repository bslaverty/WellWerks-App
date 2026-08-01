import 'operations_log_service.dart';

enum DrilloutCleanoutInputType {
  dropdown,
  numeric,
  dateTime,
  multilineText,
  chokeSelector,
  singleLineText,
}

enum DrilloutCleanoutFieldValidation {
  none,
  numeric,
  dateTime,
}

class DrilloutCleanoutFieldDefinition {
  const DrilloutCleanoutFieldDefinition({
    required this.id,
    required this.label,
    required this.inputType,
    required this.displayOrder,
    this.includeToggleLabel,
    this.options = const <String>[],
    this.unitLabel,
    this.validation = DrilloutCleanoutFieldValidation.none,
    this.reportVisible = true,
    this.workflows = const <OperationsLogWorkflow>{
      OperationsLogWorkflow.drillout,
      OperationsLogWorkflow.cleanout,
    },
  });

  final String id;
  final String label;
  final DrilloutCleanoutInputType inputType;
  final int displayOrder;
  final String? includeToggleLabel;
  final List<String> options;
  final String? unitLabel;
  final DrilloutCleanoutFieldValidation validation;
  final bool reportVisible;
  final Set<OperationsLogWorkflow> workflows;
}

class DrilloutCleanoutFieldDefinitions {
  const DrilloutCleanoutFieldDefinitions._();

  static const String operationStageId = 'operationStage';
  static const String chokeId = 'choke';
  static const String pumpRateId = 'pumpRate';
  static const String returnsRateId = 'returnsRate';
  static const String tubingPressureId = 'tubingPressure';
  static const String casingPressureId = 'casingPressure';
  static const String pumpPressureId = 'pumpPressure';
  static const String gasId = 'gas';
  static const String estimatedStsId = 'estimatedSts';
  static const String stsId = 'sts';
  static const String sandOrSolidsId = 'sandOrSolids';
  static const String plugNumberId = 'plugNumber';
  static const String surfaceTotalFluidId = 'surfaceTotalFluid';
  static const String waterHauledId = 'waterHauled';
  static const String oilHauledId = 'oilHauled';
  static const String sweepInformationId = 'sweepInformation';
  static const String tankLevelId = 'tankLevel';
  static const String notesId = 'notes';

  static const List<String> stageOptions = <String>[
    'Ready for Pressure Test',
    'Drilling Plugs',
    'Traveling to Bottom',
    'Circulating',
    'Equipment Issues',
    'POOH',
  ];

  static const List<String> gasOptions = <String>[
    'None',
    'Light',
    'Medium',
    'Heavy',
  ];

  static const List<String> sandOptions = <String>[
    'Trace',
    'Light',
    'Medium',
    'Heavy',
  ];

  static const List<DrilloutCleanoutFieldDefinition> readingFields =
      <DrilloutCleanoutFieldDefinition>[
    DrilloutCleanoutFieldDefinition(
      id: operationStageId,
      label: 'Stage',
      inputType: DrilloutCleanoutInputType.dropdown,
      displayOrder: 10,
      includeToggleLabel: 'Include Status',
      options: stageOptions,
    ),
    DrilloutCleanoutFieldDefinition(
      id: chokeId,
      label: 'Choke Selector',
      inputType: DrilloutCleanoutInputType.chokeSelector,
      displayOrder: 20,
      includeToggleLabel: 'Include Choke',
    ),
    DrilloutCleanoutFieldDefinition(
      id: pumpRateId,
      label: 'Pump Rate',
      unitLabel: 'bbl/min',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 30,
      includeToggleLabel: 'Include Pump Rate',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: returnsRateId,
      label: 'Returns',
      unitLabel: 'bbl/min',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 40,
      includeToggleLabel: 'Include Returns',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: tubingPressureId,
      label: 'Manifold PSI',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 50,
      includeToggleLabel: 'Include Manifold PSI',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: casingPressureId,
      label: 'Casing PSI',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 60,
      includeToggleLabel: 'Include Casing PSI',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: pumpPressureId,
      label: 'Pump PSI',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 70,
      includeToggleLabel: 'Include Pump PSI',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: gasId,
      label: 'Gas',
      inputType: DrilloutCleanoutInputType.dropdown,
      displayOrder: 80,
      includeToggleLabel: 'Gas',
      options: gasOptions,
    ),
    DrilloutCleanoutFieldDefinition(
      id: estimatedStsId,
      label: 'Estimated STS',
      inputType: DrilloutCleanoutInputType.dateTime,
      displayOrder: 90,
      includeToggleLabel: 'Include Estimated STS',
      validation: DrilloutCleanoutFieldValidation.dateTime,
    ),
    DrilloutCleanoutFieldDefinition(
      id: stsId,
      label: 'STS',
      inputType: DrilloutCleanoutInputType.dateTime,
      displayOrder: 100,
      includeToggleLabel: 'Include STS',
      validation: DrilloutCleanoutFieldValidation.dateTime,
    ),
    DrilloutCleanoutFieldDefinition(
      id: sandOrSolidsId,
      label: 'Sand / Solids',
      inputType: DrilloutCleanoutInputType.dropdown,
      displayOrder: 110,
      includeToggleLabel: 'Sand',
      options: sandOptions,
    ),
    DrilloutCleanoutFieldDefinition(
      id: plugNumberId,
      label: 'Plug Number',
      inputType: DrilloutCleanoutInputType.singleLineText,
      displayOrder: 120,
      includeToggleLabel: 'Include Plug Number',
    ),
    DrilloutCleanoutFieldDefinition(
      id: surfaceTotalFluidId,
      label: 'Surface Total Fluid',
      unitLabel: 'bbl',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 130,
      includeToggleLabel: 'Include Surface Total Fluid',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: waterHauledId,
      label: 'Water Hauled',
      unitLabel: 'bbl',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 140,
      includeToggleLabel: 'Include Water Hauled',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: oilHauledId,
      label: 'Oil Hauled',
      unitLabel: 'bbl',
      inputType: DrilloutCleanoutInputType.numeric,
      displayOrder: 150,
      includeToggleLabel: 'Include Oil Hauled',
      validation: DrilloutCleanoutFieldValidation.numeric,
    ),
    DrilloutCleanoutFieldDefinition(
      id: sweepInformationId,
      label: 'Coil Depth',
      unitLabel: 'ft',
      inputType: DrilloutCleanoutInputType.singleLineText,
      displayOrder: 160,
      includeToggleLabel: 'Include Coil Depth',
      reportVisible: true,
    ),
    DrilloutCleanoutFieldDefinition(
      id: tankLevelId,
      label: 'Tank Information',
      inputType: DrilloutCleanoutInputType.singleLineText,
      displayOrder: 170,
      includeToggleLabel: 'Include Tank Information',
    ),
    DrilloutCleanoutFieldDefinition(
      id: notesId,
      label: 'Notes',
      inputType: DrilloutCleanoutInputType.multilineText,
      displayOrder: 180,
      includeToggleLabel: 'Include Notes',
      reportVisible: true,
    ),
  ];

  static DrilloutCleanoutFieldDefinition? byId(String fieldId) {
    for (final field in readingFields) {
      if (field.id == fieldId) return field;
    }
    return null;
  }

  static List<DrilloutCleanoutFieldDefinition> fieldsForWorkflow(
    OperationsLogWorkflow workflow,
  ) {
    return readingFields
        .where((field) => field.workflows.contains(workflow))
        .toList(growable: false)
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  }

  static Set<String> get defaultEnabledFieldIds => <String>{
        operationStageId,
        chokeId,
        pumpRateId,
        returnsRateId,
        tubingPressureId,
        casingPressureId,
        pumpPressureId,
        gasId,
        estimatedStsId,
        stsId,
        sandOrSolidsId,
        sweepInformationId,
        tankLevelId,
        notesId,
      };
}
