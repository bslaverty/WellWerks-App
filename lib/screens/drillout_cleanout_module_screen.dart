import 'package:flutter/material.dart';

import '../services/active_workflow_mode_service.dart';
import '../services/operations_log_service.dart';
import 'drillout_shift_change_screen.dart';
import 'jsa_screen.dart';
import 'module_menu_screen.dart';
import 'operations_log_screen.dart';
import 'shift_handoff_screen.dart';

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
        const ModuleTool(
          icon: Icons.list_alt,
          title: 'Drillout Log',
          subtitle: 'Timestamped drillout readings and compact reports',
          screen: OperationsLogScreen(
            workflow: OperationsLogWorkflow.drillout,
            title: 'Drillout Log',
          ),
        ),
        const ModuleTool(
          icon: Icons.list_alt,
          title: 'Cleanout Log',
          subtitle: 'Timestamped cleanout readings and compact reports',
          screen: OperationsLogScreen(
            workflow: OperationsLogWorkflow.cleanout,
            title: 'Cleanout Log',
          ),
        ),
        const ModuleTool(
          icon: Icons.swap_horiz,
          title: 'Drillout Handoff',
          subtitle: 'Share/import drillout and cleanout active job context',
          screen: ShiftHandoffScreen(),
        ),
      ],
    );
  }
}
