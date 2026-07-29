import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/services/operator_profile_service.dart';

void main() {
  final service = OperatorProfileService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('operator profile saves locally and keeps persistent id', () async {
    final first = await service.load();
    expect(first.operatorId, isNotEmpty);
    expect(first.name, isEmpty);

    await service.updateProfile(name: 'Jane Doe', initials: 'JD');
    final second = await service.load();

    expect(second.operatorId, first.operatorId);
    expect(second.name, 'Jane Doe');
    expect(second.initials, 'JD');
  });

  test('operator initials are suggested from name', () {
    expect(service.suggestInitials('Jane Doe'), 'JD');
    expect(service.suggestInitials('Mary Ann Smith'), 'MAS');
  });
}
