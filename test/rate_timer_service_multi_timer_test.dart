import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/services/rate_timer_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores separate active timers for the same calculator', () async {
    final service = RateTimerService();

    final first = await service.createState(
      calculatorId: 'fs3',
      calculatorTitle: 'FS3 Tank',
      wellOrJob: 'Tank A',
      durationSeconds: 300,
    );
    final second = (await service.createState(
      calculatorId: 'fs3',
      calculatorTitle: 'FS3 Tank',
      wellOrJob: 'Tank B',
      durationSeconds: 420,
    ))
        .copyWith(
      instanceId: 'fs3-instance-b',
      startedAtMs:
          DateTime.now().add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      endsAtMs: DateTime.now()
          .add(const Duration(seconds: 421))
          .millisecondsSinceEpoch,
    );

    await service.saveActiveTimer(first);
    await service.saveActiveTimer(second);

    expect(
        await service.loadActiveTimerForInstance(first.instanceId), isNotNull);
    expect(
        await service.loadActiveTimerForInstance(second.instanceId), isNotNull);
    expect(await service.loadActiveTimerForCalculator('fs3'), isNotNull);

    await service.clearActiveTimer(instanceId: first.instanceId);

    expect(await service.loadActiveTimerForInstance(first.instanceId), isNull);
    expect(
        await service.loadActiveTimerForInstance(second.instanceId), isNotNull);
    expect((await service.loadActiveTimer())?.instanceId, second.instanceId);
  });
}
