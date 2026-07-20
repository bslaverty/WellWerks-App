import 'package:flutter/material.dart';

import '../services/active_workflow_mode_service.dart';
import 'drillout_shift_change_screen.dart';
import 'jsa_screen.dart';
import 'module_menu_screen.dart';

class DrilloutCleanoutModuleScreen extends StatelessWidget {
  const DrilloutCleanoutModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final workflow = ActiveWorkflowModeService.instance.mode.value;
    final subtitle = workflow == ActiveWorkflowMode.cleanout
        ? 'Active workflow: Cleanout'
        : 'Active workflow: Drillout';

    return ModuleMenuScreen(
      title: 'Drillout / Cleanout',
      showHomeButton: true,
      tools: [
        ModuleTool(
          icon: Icons.text_snippet_outlined,
          title: 'Shift Change / Update',
          subtitle: '$subtitle (switch anytime inside module)',
          screen: DrilloutShiftChangeScreen(initialWorkflow: workflow),
        ),
        const ModuleTool(
          icon: Icons.fact_check,
          title: 'JSA',
          subtitle: 'Prefills from active workflow and active job context',
          screen: JsaScreen(),
        ),
      ],
    );
  }
}
