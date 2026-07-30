import 'package:flutter/material.dart';

import 'bottoms_up_screen.dart';
import 'chart_reference_screen.dart';
import 'conversion_calculator_screen.dart';
import 'gas_accum_screen.dart';
import 'module_menu_screen.dart';
import 'multiple_choke_screen.dart';

class CompletionsCalculatorsScreen extends StatelessWidget {
  const CompletionsCalculatorsScreen({super.key});

  Widget _chloridesCalculatorScreen() {
    return const ChartReferenceScreen(
      title: 'Chlorides Chart',
      description:
          'Chlorides reference table from the web app source with Brix to SG conversion.',
      showBrixTool: false,
      showChloridesCalculator: true,
      enableSearch: true,
      sections: [
        ChartSection(
          title: 'Water Weight and Chlorides',
          columns: ['SP.GR.', '#/G', 'CLPPM'],
          rows: [
            ['1.002', '8.36', '1755'],
            ['1.004', '8.38', '3511'],
            ['1.006', '8.40', '5267'],
            ['1.008', '8.41', '7023'],
            ['1.010', '8.43', '8779'],
            ['1.086', '9.06', '75500'],
            ['1.088', '9.08', '77260'],
            ['1.090', '9.10', '79010'],
            ['1.092', '9.11', '80770'],
            ['1.170', '9.76', '149200'],
            ['1.172', '9.78', '151000'],
            ['1.174', '9.80', '152700'],
            ['1.176', '9.81', '154501'],
          ],
        ),
        ChartSection(
          title: 'Brix to SG Reference',
          columns: ['Brix', 'SG'],
          rows: [
            ['0', '1.0000'],
            ['5', '1.0197'],
            ['10', '1.0400'],
            ['15', '1.0607'],
            ['20', '1.0829'],
            ['25', '1.1068'],
            ['30', '1.1325'],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleMenuScreen(
      title: 'Calculators',
      showHomeButton: true,
      tools: [
        const ModuleTool(
          icon: Icons.local_fire_department,
          title: 'Gas Accum Calculator',
          subtitle: 'Hourly gas rate from totalizer readings',
          screen: GasAccumScreen(),
        ),
        const ModuleTool(
          icon: Icons.arrow_downward,
          title: 'Bottoms Up Calculator',
          subtitle: 'Pipe volume, lag time, and ETA',
          screen: BottomsUpScreen(),
        ),
        const ModuleTool(
          icon: Icons.tune,
          title: 'Multiple Choke Calculator',
          subtitle: 'Equivalent choke and total flow area',
          screen: MultipleChokeScreen(),
        ),
        const ModuleTool(
          icon: Icons.straighten,
          title: 'Conversion Calculator',
          subtitle: 'Length, volume, pressure, flow, gas, and oilfield',
          screen: ConversionCalculatorScreen(),
        ),
        ModuleTool(
          icon: Icons.science,
          title: 'Chlorides Calculator',
          subtitle: 'Chlorides and salinity calculator and chart lookup',
          screen: _chloridesCalculatorScreen(),
        ),
      ],
    );
  }
}
