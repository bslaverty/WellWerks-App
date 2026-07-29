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

    expect(find.text('Company'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Jane Doe');
    await tester.enterText(find.byType(TextField).last, 'JD');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final profile = await OperatorProfileService.instance.load();
    expect(profile.name, 'Jane Doe');
    expect(profile.initials, 'JD');
    expect(profile.operatorId, isNotEmpty);
  });
}
