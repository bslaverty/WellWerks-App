import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/services/shift_handoff_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Build 182 handoff history stores newest first', () async {
    final service = ShiftHandoffHistoryService();

    await service.appendEntry(
      const ShiftHandoffHistoryEntry(
        action: 'import',
        timestampIso: '2026-07-27T10:00:00.000Z',
        handoffId: 'handoff-1',
        sourceJobId: 'job-1',
        entriesAdded: 2,
        duplicatesSkipped: 1,
        conflictCount: 0,
        importedConflictChoices: 0,
      ),
    );
    await service.appendEntry(
      const ShiftHandoffHistoryEntry(
        action: 'export',
        timestampIso: '2026-07-27T11:00:00.000Z',
        handoffId: 'handoff-2',
        sourceJobId: 'job-1',
        entriesAdded: 5,
        duplicatesSkipped: 0,
        conflictCount: 0,
        importedConflictChoices: 0,
      ),
    );

    final history = await service.loadHistory();
    expect(history.length, 2);
    expect(history.first.handoffId, 'handoff-2');
    expect(history.last.handoffId, 'handoff-1');
  });

  test('Build 182 handoff history gracefully handles corrupted data', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{
        'wellwerks_shift_handoff_history_v1': '{not-json',
      },
    );
    final service = ShiftHandoffHistoryService();
    final history = await service.loadHistory();
    expect(history, isEmpty);
  });
}
