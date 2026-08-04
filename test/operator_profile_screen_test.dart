import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/operator_profile_screen.dart';
import 'package:wellwerks/services/operator_profile_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('operator profile saves name and initials locally',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OperatorProfileScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Jane Doe');
    await tester.enterText(find.widgetWithText(TextField, 'Initials'), 'JD');
    await tester.enterText(
      find.widgetWithText(TextField, 'Company'),
      'Mach Energy',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Job Title'),
      'Production Operator',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final profile = await OperatorProfileService.instance.load();
    expect(profile.name, 'Jane Doe');
    expect(profile.initials, 'JD');
    expect(profile.company, 'Mach Energy');
    expect(profile.jobTitle, 'Production Operator');
    expect(profile.operatorId, isNotEmpty);
  });
}
