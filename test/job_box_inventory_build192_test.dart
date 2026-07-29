import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_box_inventory.dart';
import 'package:wellwerks/services/job_box_inventory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Build 192 positive chokes include 12/64 through 64/64', () {
    final chokes = JobBoxInventoryCatalog.defaultItems
        .where((item) =>
            item.section == JobBoxInventoryCatalog.positiveChokesSection)
        .map((item) => item.name)
        .toList(growable: false);

    expect(chokes.first, '12/64');
    expect(chokes.last, '64/64');
    expect(chokes.length, 53);
  });

  test('Build 192 inventory drafts are isolated by source', () async {
    final service = JobBoxInventoryService();

    final production = JobBoxInventoryRecord.createDefault().copyWith(
      source: JobBoxInventorySource.production,
      jobBoxNumber: 'PROD-1',
    );
    final completions = JobBoxInventoryRecord.createDefault().copyWith(
      source: JobBoxInventorySource.completions,
      jobBoxNumber: 'COMP-1',
    );

    await service.saveWorkingDraft(
      production,
      source: JobBoxInventorySource.production,
    );
    await service.saveWorkingDraft(
      completions,
      source: JobBoxInventorySource.completions,
    );

    final loadedProduction = await service.loadWorkingDraft(
      source: JobBoxInventorySource.production,
    );
    final loadedCompletions = await service.loadWorkingDraft(
      source: JobBoxInventorySource.completions,
    );

    expect(loadedProduction, isNotNull);
    expect(loadedCompletions, isNotNull);
    expect(loadedProduction!.jobBoxNumber, 'PROD-1');
    expect(loadedCompletions!.jobBoxNumber, 'COMP-1');
    expect(
      loadedProduction.source,
      JobBoxInventorySource.production,
    );
    expect(
      loadedCompletions.source,
      JobBoxInventorySource.completions,
    );
  });
}
