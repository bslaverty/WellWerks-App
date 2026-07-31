import 'package:flutter/material.dart';

import '../models/job_box_inventory.dart';
import 'job_box_inventory_screen.dart';
import 'jsa_screen.dart';
import 'module_menu_screen.dart';
import 'operations_log_screen.dart';
import 'rate_calculator_menu_screen.dart';

class DrilloutCleanoutModuleScreen extends StatelessWidget {
  const DrilloutCleanoutModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuleMenuScreen(
      title: 'Drillout / Cleanout',
      showHomeButton: true,
      tools: [
        ModuleTool(
          icon: Icons.list_alt,
          title: 'Operations Log',
          subtitle:
              'Timestamped drillout and cleanout readings, reports, and QR sharing.',
          screen: OperationsLogScreen(),
        ),
        ModuleTool(
          icon: Icons.speed,
          title: 'Rate Calculator',
          subtitle: 'FS3, SandX, flowback, and production rate tools',
          screen: RateCalculatorMenuScreen(),
        ),
        ModuleTool(
          icon: Icons.fact_check,
          title: 'JSA',
          subtitle: 'Prefills from active workflow and active job context',
          screen: JsaScreen(),
        ),
        ModuleTool(
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
