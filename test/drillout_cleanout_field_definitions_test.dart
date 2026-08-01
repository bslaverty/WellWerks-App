import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/services/drillout_cleanout_field_definitions.dart';
import 'package:wellwerks/services/drillout_cleanout_stage_service.dart';
import 'package:wellwerks/services/operations_log_field_config_service.dart';

void main() {
  test('shared field definition source drives stage list', () {
    expect(
      DrilloutCleanoutStageService.stageOptions,
      equals(DrilloutCleanoutFieldDefinitions.stageOptions),
    );
    expect(
      DrilloutCleanoutFieldDefinitions.stageOptions,
      contains('Traveling to Bottom'),
    );
  });

  test('operations log configurable fields come from shared definitions', () {
    final configurableIds = OperationsLogFieldConfigService.configurableFields
        .map((item) => item.id)
        .toSet();
    final sharedIds =
        DrilloutCleanoutFieldDefinitions.readingFields.map((f) => f.id).toSet();

    expect(configurableIds, equals(sharedIds));
    expect(configurableIds, contains(DrilloutCleanoutFieldDefinitions.gasId));
    expect(
      configurableIds,
      contains(DrilloutCleanoutFieldDefinitions.sandOrSolidsId),
    );
    expect(
      configurableIds,
      contains(DrilloutCleanoutFieldDefinitions.estimatedStsId),
    );
    expect(configurableIds, contains(DrilloutCleanoutFieldDefinitions.stsId));
    expect(
      configurableIds,
      contains(DrilloutCleanoutFieldDefinitions.returnsRateId),
    );
    expect(
      configurableIds,
      contains(DrilloutCleanoutFieldDefinitions.sweepInformationId),
    );
    expect(configurableIds, isNot(contains('waterRate')));
    expect(configurableIds, isNot(contains('flowRate')));
  });

  test('shared dropdown options match expected gas and sand presets', () {
    expect(
      DrilloutCleanoutFieldDefinitions.gasOptions,
      equals(const <String>['None', 'Light', 'Medium', 'Heavy']),
    );
    expect(
      DrilloutCleanoutFieldDefinitions.sandOptions,
      equals(const <String>['Trace', 'Light', 'Medium', 'Heavy']),
    );
  });

  test('default operations log fields match build 191 shared configuration',
      () {
    expect(
      DrilloutCleanoutFieldDefinitions.defaultEnabledFieldIds,
      equals(<String>{
        DrilloutCleanoutFieldDefinitions.operationStageId,
        DrilloutCleanoutFieldDefinitions.chokeId,
        DrilloutCleanoutFieldDefinitions.pumpRateId,
        DrilloutCleanoutFieldDefinitions.returnsRateId,
        DrilloutCleanoutFieldDefinitions.casingPressureId,
        DrilloutCleanoutFieldDefinitions.pumpPressureId,
        DrilloutCleanoutFieldDefinitions.tubingPressureId,
        DrilloutCleanoutFieldDefinitions.gasId,
        DrilloutCleanoutFieldDefinitions.estimatedStsId,
        DrilloutCleanoutFieldDefinitions.stsId,
        DrilloutCleanoutFieldDefinitions.sandOrSolidsId,
        DrilloutCleanoutFieldDefinitions.sweepInformationId,
        DrilloutCleanoutFieldDefinitions.notesId,
      }),
    );
  });
}
