import 'package:flutter/material.dart';

import '../models/job_box_inventory.dart';
import '../services/active_workflow_mode_service.dart';
import 'drillout_shift_change_screen.dart';
import 'job_box_inventory_screen.dart';
import 'jsa_screen.dart';
import 'module_menu_screen.dart';
import 'operations_log_screen.dart';
import 'rate_calculator_menu_screen.dart';

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
        const ModuleTool(
          icon: Icons.list_alt,
          title: 'Operations Log',
          subtitle:
              'Timestamped drillout and cleanout readings, reports, and QR sharing.',
          screen: OperationsLogScreen(),
        ),
        const ModuleTool(
          icon: Icons.speed,
          title: 'Rate Calculator',
          subtitle: 'FS3, SandX, flowback, and production rate tools',
          screen: RateCalculatorMenuScreen(),
        ),
        const ModuleTool(
          icon: Icons.timer_outlined,
          title: 'STS',
          subtitle: 'Open STS entry and save directly to Operations Log',
          screen: OperationsLogScreen(
            title: 'STS',
            openAddStsOnLoad: true,
          ),
        ),
        ModuleTool(
          icon: Icons.text_snippet_outlined,
          title: 'Shift Update',
          subtitle: '$subtitle (switch anytime inside module)',
          screen: DrilloutShiftChangeScreen(
            initialWorkflow: workflow,
            initialMode: DrilloutShiftLaunchMode.update,
          ),
        ),
        ModuleTool(
          icon: Icons.preview_outlined,
          title: 'Text Preview',
          subtitle: 'Preview update text from current workflow values',
          screen: DrilloutShiftChangeScreen(
            initialWorkflow: workflow,
            initialMode: DrilloutShiftLaunchMode.update,
            initialAction: DrilloutShiftLaunchAction.preview,
          ),
        ),
        ModuleTool(
          icon: Icons.copy_outlined,
          title: 'Copy Update',
          subtitle: 'Copy and log update text to Operations Log',
          screen: DrilloutShiftChangeScreen(
            initialWorkflow: workflow,
            initialMode: DrilloutShiftLaunchMode.update,
            initialAction: DrilloutShiftLaunchAction.copy,
          ),
        ),
        const ModuleTool(
          icon: Icons.fact_check,
          title: 'JSA',
          subtitle: 'Prefills from active workflow and active job context',
          screen: JsaScreen(),
        ),
        const ModuleTool(
          icon: Icons.inventory_2_outlined,
          title: 'Job Box Inventory',
          subtitle: 'Track completions job box inventory and sync drafts',
          screen: JobBoxInventoryScreen(
            source: JobBoxInventorySource.completions,
          ),
        ),
      ],
    );
  }
}
