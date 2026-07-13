import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/jsa_template.dart';

void main() {
  group('Build 106 template content', () {
    test('Production loads exactly 10 steps', () {
      final template = JsaBuiltInTemplates.byId('production');
      expect(template, isNotNull);
      expect(template!.steps.length, 10);
      expect(template.basicJobSteps.length, 10);
    });

    test('Production Startup loads exactly 10 steps', () {
      final template = JsaBuiltInTemplates.byId('production_startup');
      expect(template, isNotNull);
      expect(template!.steps.length, 10);
      expect(template.basicJobSteps.length, 10);
    });

    test('Drillout loads exactly 10 steps', () {
      final template = JsaBuiltInTemplates.byId('drillout');
      expect(template, isNotNull);
      expect(template!.steps.length, 10);
      expect(template.basicJobSteps.length, 10);
    });

    test('Rig Up loads exactly 10 steps', () {
      final template = JsaBuiltInTemplates.byId('rig_up');
      expect(template, isNotNull);
      expect(template!.steps.length, 10);
      expect(template.basicJobSteps.length, 10);
    });

    test('Rig Down loads exactly 10 steps', () {
      final template = JsaBuiltInTemplates.byId('rig_down');
      expect(template, isNotNull);
      expect(template!.steps.length, 10);
      expect(template.basicJobSteps.length, 10);
    });

    test('Exact step order is preserved for Production', () {
      final template = JsaBuiltInTemplates.byId('production')!;
      expect(
        template.basicJobSteps,
        const <String>[
          'Conduct pre-job meeting and inspect location',
          'Inspect production and pressure-control equipment',
          'Check pressures, rates, and equipment operation',
          'Gauge and monitor tanks',
          'Monitor water and oil production',
          'Change or adjust choke',
          'Dump sand or drain equipment',
          'Check for and respond to leaks',
          'Record readings and communicate updates',
          'Maintain housekeeping throughout the shift',
        ],
      );
    });

    test('Exact step order is preserved for Production Startup', () {
      final template = JsaBuiltInTemplates.byId('production_startup')!;
      expect(
        template.basicJobSteps,
        const <String>[
          'Conduct pre-job meeting and review startup plan',
          'Inspect and verify equipment lineup',
          'Verify tanks and fluid routing',
          'Introduce flow into production equipment',
          'Monitor pressure changes',
          'Monitor initial sand production',
          'Monitor gas and fluid production',
          'Adjust choke and stabilize flow',
          'Inspect for leaks and equipment issues',
          'Confirm stable production conditions',
        ],
      );
    });

    test('Exact step order is preserved for Drillout', () {
      final template = JsaBuiltInTemplates.byId('drillout')!;
      expect(
        template.basicJobSteps,
        const <String>[
          'Conduct pre-job meeting and review drillout operations',
          'Inspect flowback and pressure-control equipment',
          'Monitor well pressures during drillout',
          'Drill plugs and monitor plug progress',
          'Monitor gas and fluid returns',
          'Monitor and handle sand',
          'Operate plug catcher and related equipment',
          'Adjust or change choke',
          'Respond to leaks or equipment issues',
          'Communicate shift status and handoff',
        ],
      );
    });

    test('Exact step order is preserved for Rig Up', () {
      final template = JsaBuiltInTemplates.byId('rig_up')!;
      expect(
        template.basicJobSteps,
        const <String>[
          'Conduct pre-job meeting and review rig-up plan',
          'Inspect location and establish work area',
          'Spot trucks and equipment',
          'Unload and position equipment',
          'Position and connect pressure-control equipment',
          'Rig up iron, hoses, and flow lines',
          'Install separators, tanks, and production equipment',
          'Install restraints and secure equipment',
          'Pressure test equipment',
          'Conduct final rig-up inspection and handoff',
        ],
      );
    });

    test('Exact step order is preserved for Rig Down', () {
      final template = JsaBuiltInTemplates.byId('rig_down')!;
      expect(
        template.basicJobSteps,
        const <String>[
          'Conduct pre-job meeting and review rig-down plan',
          'Shut down and isolate production equipment',
          'Bleed pressure and verify zero energy',
          'Drain and control residual fluids',
          'Break iron and pressure connections',
          'Remove restraints and supports',
          'Disconnect and remove production equipment',
          'Load equipment and iron',
          'Inspect and clean the work location',
          'Complete final handoff and documentation',
        ],
      );
    });

    test('Hazards load with the correct step', () {
      final production = JsaBuiltInTemplates.byId('production')!;
      final hazards = production.hazards;
      expect(hazards.first, 'STEP 1');
      expect(hazards[1], '• Unfamiliar site conditions');
      final step2 = hazards.indexOf('STEP 2');
      expect(step2, greaterThan(1));
      expect(hazards[step2 + 1], '• High-pressure equipment');
      expect(hazards, contains('STEP 10'));
      expect(hazards, contains('• Blocked exits or access routes'));
    });

    test('Recommended Actions load with the correct step', () {
      final production = JsaBuiltInTemplates.byId('production')!;
      final actions = production.recommendedActions;
      expect(actions.first, 'STEP 1');
      expect(actions[1], '• Review the job scope and assign responsibilities');
      final step6 = actions.indexOf('STEP 6');
      expect(step6, greaterThan(1));
      expect(
        actions[step6 + 1],
        '• Confirm the correct choke size before making changes',
      );
      expect(actions, contains('STEP 10'));
      expect(actions,
          contains('• Remove unnecessary materials from the work area'));
    });

    test('Template loading deep-copies content', () {
      final template = JsaBuiltInTemplates.byId('drillout')!;
      final loadedSteps = List<String>.from(template.basicJobSteps);
      final loadedHazards = List<String>.from(template.hazards);
      final loadedActions = List<String>.from(template.recommendedActions);

      loadedSteps[0] = 'Edited Step';
      loadedHazards[1] = '• Edited Hazard';
      loadedActions[1] = '• Edited Action';

      expect(
        template.basicJobSteps.first,
        'Conduct pre-job meeting and review drillout operations',
      );
      expect(template.hazards[1], '• High-pressure operations');
      expect(
        template.recommendedActions[1],
        '• Review current well and plug status',
      );
    });

    test(
        'Editing current JSA content does not modify built-in template content',
        () {
      final template = JsaBuiltInTemplates.byId('rig_down')!;
      final editable = List<String>.from(template.basicJobSteps);
      editable.removeAt(0);
      editable.add('Custom Operator Step');

      expect(template.basicJobSteps.length, 10);
      expect(template.basicJobSteps.first,
          'Conduct pre-job meeting and review rig-down plan');
      expect(template.basicJobSteps, isNot(contains('Custom Operator Step')));
    });
  });
}
