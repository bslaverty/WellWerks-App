class JsaTemplateDefinition {
  const JsaTemplateDefinition({
    required this.id,
    required this.name,
    this.steps = const <JsaTemplateStep>[],
    this.requiredPpe = const <String>[],
    this.specialInstructions = const <String>[],
  });

  final String id;
  final String name;
  final List<JsaTemplateStep> steps;

  List<String> get basicJobSteps {
    return steps.map((step) => step.basicJobStep).toList(growable: false);
  }

  List<String> get hazards {
    return _flattenByStep(
      steps,
      (step) => step.hazards,
    );
  }

  List<String> get recommendedActions {
    return _flattenByStep(
      steps,
      (step) => step.recommendedActions,
    );
  }

  List<String> _flattenByStep(
    List<JsaTemplateStep> source,
    List<String> Function(JsaTemplateStep step) pickItems,
  ) {
    final output = <String>[];
    for (var index = 0; index < source.length; index++) {
      output.add('STEP ${index + 1}');
      for (final item in pickItems(source[index])) {
        output.add('• $item');
      }
    }
    return output;
  }

  // Reserved for future builds so we can extend without breaking templates.
  final List<String> requiredPpe;
  final List<String> specialInstructions;
}

class JsaTemplateStep {
  const JsaTemplateStep({
    required this.basicJobStep,
    this.hazards = const <String>[],
    this.recommendedActions = const <String>[],
  });

  final String basicJobStep;
  final List<String> hazards;
  final List<String> recommendedActions;
}

class JsaBuiltInTemplates {
  static const List<JsaTemplateDefinition> all = <JsaTemplateDefinition>[
    JsaTemplateDefinition(
      id: 'production',
      name: 'Production',
      steps: <JsaTemplateStep>[
        JsaTemplateStep(
          basicJobStep: 'Conduct pre-job meeting and inspect location',
          hazards: <String>[
            'Unfamiliar site conditions',
            'Vehicle and equipment traffic',
            'Poor lighting',
            'Uneven, muddy, icy, or slippery ground',
            'Wildlife, insects, and weather exposure',
            'Unidentified pressure or fluid hazards',
          ],
          recommendedActions: <String>[
            'Review the job scope and assign responsibilities',
            'Identify emergency equipment, exits, muster area, and medical plan',
            'Inspect walking and working surfaces',
            'Confirm adequate lighting',
            'Maintain situational awareness around moving vehicles and equipment',
            'Review current weather conditions',
            'Stop work if conditions become unsafe',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Inspect production and pressure-control equipment',
          hazards: <String>[
            'High-pressure equipment',
            'Leaks or damaged iron',
            'Loose connections',
            'Stored energy',
            'Unexpected equipment movement',
            'Pinch points and sharp edges',
          ],
          recommendedActions: <String>[
            'Inspect iron, valves, hoses, restraints, tanks, separators, and connections',
            'Check for visible damage, leaks, washout, vibration, or loose components',
            'Verify restraints and supports are properly installed',
            'Do not tighten or repair equipment while pressured',
            'Isolate and bleed pressure before making repairs',
            'Stand clear of potential pressure-release paths',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Check pressures, rates, and equipment operation',
          hazards: <String>[
            'High pressure',
            'Unexpected pressure changes',
            'Flying debris',
            'Leaking gas or fluids',
            'Noise exposure',
            'Equipment failure',
          ],
          recommendedActions: <String>[
            'Approach gauges and equipment from a safe position',
            'Do not stand directly in front of valves, unions, caps, or fittings',
            'Monitor pressure changes closely',
            'Use proper hearing and eye protection',
            'Report abnormal pressure, vibration, noise, or leaks immediately',
            'Shut down or isolate equipment if unsafe conditions develop',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Gauge and monitor tanks',
          hazards: <String>[
            'Hydrocarbon vapors',
            'H₂S or other hazardous gases',
            'Falls from ladders or tank stairs',
            'Slippery surfaces',
            'Static electricity',
            'Overflow or release of fluids',
          ],
          recommendedActions: <String>[
            'Test the atmosphere where required',
            'Approach tanks from upwind',
            'Use designated stairs, ladders, platforms, and handrails',
            'Maintain three points of contact',
            'Do not climb on unauthorized tank surfaces',
            'Open hatches slowly while standing to the side',
            'Keep ignition sources away',
            'Monitor tank levels to prevent overflow',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Monitor water and oil production',
          hazards: <String>[
            'Pressurized fluids',
            'Hot fluids or equipment',
            'Leaking lines and fittings',
            'Slips from spilled fluids',
            'Incorrect valve alignment',
            'Tank overflow',
          ],
          recommendedActions: <String>[
            'Verify correct valve positions before making changes',
            'Monitor tanks or meters for abnormal readings',
            'Keep fluid-transfer areas clean',
            'Clean or barricade spills promptly',
            'Never open pressurized equipment',
            'Communicate production changes to affected personnel',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Change or adjust choke',
          hazards: <String>[
            'High pressure',
            'Stored energy',
            'Flying debris',
            'Unexpected flow changes',
            'Hot or damaged equipment',
            'Pinch points',
          ],
          recommendedActions: <String>[
            'Confirm the correct choke size before making changes',
            'Communicate the intended change',
            'Stand in a safe position and outside the line of fire',
            'Follow the approved choke-change procedure',
            'Isolate and bleed pressure when required',
            'Monitor pressure and flow after the adjustment',
            'Stop immediately if equipment behaves abnormally',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Dump sand or drain equipment',
          hazards: <String>[
            'High pressure',
            'Abrasive sand and fluid discharge',
            'Unexpected valve movement',
            'Flying debris',
            'Slips and spills',
            'Exposure to hydrocarbons or chemicals',
          ],
          recommendedActions: <String>[
            'Verify the correct dump path and receiving equipment',
            'Stand clear of discharge lines and outlets',
            'Open valves slowly',
            'Monitor tank and containment capacity',
            'Wear required eye, face, hand, and hearing protection',
            'Stop dumping if lines plug, leak, vibrate, or move unexpectedly',
            'Isolate and bleed pressure before clearing restrictions',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Check for and respond to leaks',
          hazards: <String>[
            'High-pressure release',
            'Flammable gas or liquids',
            'H₂S exposure',
            'Fire or explosion',
            'Slippery surfaces',
            'Unexpected equipment failure',
          ],
          recommendedActions: <String>[
            'Do not attempt to tighten a pressurized connection',
            'Move personnel away from the affected area',
            'Eliminate ignition sources when safe',
            'Notify the appropriate supervisor or company representative',
            'Isolate and bleed pressure before repairs',
            'Use gas detection where required',
            'Contain and report spills according to site procedures',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Record readings and communicate updates',
          hazards: <String>[
            'Distraction near operating equipment',
            'Walking while using a phone',
            'Incorrect or missed readings',
            'Poor communication between shifts',
          ],
          recommendedActions: <String>[
            'Move to a safe location before entering information',
            'Verify readings before saving or sending',
            'Clearly communicate pressure, rate, tank, sand, choke, and equipment changes',
            'Document abnormal conditions and corrective actions',
            'Provide an accurate shift handoff',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Maintain housekeeping throughout the shift',
          hazards: <String>[
            'Trips and falls',
            'Tools or hoses in walkways',
            'Fluid spills',
            'Improperly stored equipment',
            'Blocked exits or access routes',
          ],
          recommendedActions: <String>[
            'Keep walkways, stairs, and work areas clear',
            'Store tools and equipment properly',
            'Route hoses and cords away from walking paths',
            'Clean spills promptly',
            'Keep emergency equipment and exits accessible',
            'Remove unnecessary materials from the work area',
          ],
        ),
      ],
    ),
    JsaTemplateDefinition(
      id: 'production_startup',
      name: 'Production Startup',
      steps: <JsaTemplateStep>[
        JsaTemplateStep(
          basicJobStep: 'Conduct pre-job meeting and review startup plan',
          hazards: <String>[
            'Unclear responsibilities',
            'Changing site conditions',
            'Simultaneous operations',
            'Poor communication',
            'Unidentified pressure or flow hazards',
          ],
          recommendedActions: <String>[
            'Review startup procedure and expected flow path',
            'Assign responsibilities and establish communication',
            'Identify emergency shutdown procedures',
            'Review muster area and medical plan',
            'Confirm all affected personnel are ready before startup',
            'Stop work if conditions differ from the approved plan',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Inspect and verify equipment lineup',
          hazards: <String>[
            'Incorrect valve alignment',
            'Closed or blocked flow path',
            'Damaged equipment',
            'Stored pressure',
            'Loose connections',
            'Unexpected fluid release',
          ],
          recommendedActions: <String>[
            'Walk the complete flow path before startup',
            'Verify valves are correctly aligned',
            'Confirm tanks and receiving equipment have available capacity',
            'Inspect iron, hoses, separators, restraints, and connections',
            'Verify drains and dump lines are correctly routed',
            'Do not tighten or repair pressured equipment',
            'Isolate and bleed pressure before repairs',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Verify tanks and fluid routing',
          hazards: <String>[
            'Tank overflow',
            'Incorrect tank routing',
            'Hydrocarbon vapors',
            'H₂S exposure',
            'Fluid spills',
            'Static or ignition hazards',
          ],
          recommendedActions: <String>[
            'Confirm available tank capacity',
            'Verify water and oil routing',
            'Check valve positions before introducing flow',
            'Approach tanks from upwind',
            'Use gas detection where required',
            'Keep ignition sources away',
            'Monitor tanks continuously during initial startup',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Introduce flow into production equipment',
          hazards: <String>[
            'Rapid pressure changes',
            'High-pressure release',
            'Equipment movement',
            'Flying debris',
            'Unexpected gas or fluid flow',
            'Noise exposure',
          ],
          recommendedActions: <String>[
            'Confirm personnel are clear before introducing flow',
            'Stand outside the line of fire',
            'Open valves slowly and in a controlled manner',
            'Closely monitor pressures and equipment',
            'Maintain communication during startup',
            'Stop flow immediately if equipment leaks, moves, or behaves abnormally',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Monitor pressure changes',
          hazards: <String>[
            'Pressure spikes',
            'Overpressure',
            'Gauge or equipment failure',
            'Stored energy',
            'Unexpected valve movement',
          ],
          recommendedActions: <String>[
            'Monitor tubing and casing pressure closely',
            'Verify equipment pressure ratings',
            'Maintain a safe position while reading gauges',
            'Never stand directly in front of unions, caps, valves, or fittings',
            'Communicate abnormal pressure changes immediately',
            'Shut down or isolate equipment when unsafe conditions develop',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Monitor initial sand production',
          hazards: <String>[
            'Abrasive sand',
            'Plugged equipment',
            'Washout',
            'High-pressure discharge',
            'Equipment vibration or movement',
          ],
          recommendedActions: <String>[
            'Monitor sand equipment continuously during initial flow',
            'Dump sand as required',
            'Watch for abnormal pressure differential or restricted flow',
            'Inspect for vibration, leaks, and signs of washout',
            'Stand clear of dump and discharge paths',
            'Isolate and bleed pressure before clearing restrictions',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Monitor gas and fluid production',
          hazards: <String>[
            'Unexpected gas volume',
            'Flammable atmosphere',
            'H₂S or hazardous gas',
            'Fluid surges',
            'Separator upset',
            'Tank overflow',
          ],
          recommendedActions: <String>[
            'Monitor gas, water, and oil production closely',
            'Use gas detection where required',
            'Maintain adequate tank capacity',
            'Watch for fluid surges and unstable flow',
            'Verify separators and production equipment are operating correctly',
            'Communicate major production changes',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Adjust choke and stabilize flow',
          hazards: <String>[
            'High pressure',
            'Sudden flow changes',
            'Stored energy',
            'Flying debris',
            'Equipment failure',
            'Pinch points',
          ],
          recommendedActions: <String>[
            'Confirm choke changes before adjustment',
            'Communicate each intended change',
            'Stand outside the line of fire',
            'Follow approved choke-change procedures',
            'Make controlled adjustments',
            'Monitor pressures, rates, and equipment after each change',
            'Allow conditions to stabilize before additional changes when possible',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Inspect for leaks and equipment issues',
          hazards: <String>[
            'High-pressure leaks',
            'Hydrocarbon release',
            'Fire or explosion',
            'H₂S exposure',
            'Equipment failure',
            'Slips from spilled fluids',
          ],
          recommendedActions: <String>[
            'Continuously inspect equipment during startup',
            'Do not tighten pressured connections',
            'Move personnel away from leaking equipment',
            'Isolate and bleed pressure before repairs',
            'Eliminate ignition sources when safe',
            'Contain and report spills',
            'Document equipment issues and corrective actions',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Confirm stable production conditions',
          hazards: <String>[
            'Unrecognized changing conditions',
            'Incorrect readings',
            'Equipment upset',
            'Poor shift communication',
          ],
          recommendedActions: <String>[
            'Verify pressures and production rates are stable',
            'Confirm tank routing and available capacity',
            'Verify sand handling is under control',
            'Record final startup readings',
            'Communicate current choke and equipment status',
            'Document abnormal conditions',
            'Provide a clear handoff to production personnel',
          ],
        ),
      ],
    ),
    JsaTemplateDefinition(
      id: 'drillout',
      name: 'Drillout',
      steps: <JsaTemplateStep>[
        JsaTemplateStep(
          basicJobStep:
              'Conduct pre-job meeting and review drillout operations',
          hazards: <String>[
            'High-pressure operations',
            'Simultaneous operations',
            'Changing well conditions',
            'Poor communication',
            'Unclear responsibilities',
            'Moving equipment',
          ],
          recommendedActions: <String>[
            'Review current well and plug status',
            'Discuss expected operations and pressure conditions',
            'Assign responsibilities',
            'Establish communication between flowback, coil, and company personnel',
            'Review emergency shutdown procedures and medical plan',
            'Identify line-of-fire areas',
            'Stop work if conditions become unsafe or unclear',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Inspect flowback and pressure-control equipment',
          hazards: <String>[
            'High pressure',
            'Stored energy',
            'Damaged or washed equipment',
            'Loose connections',
            'Equipment movement',
            'Leaks',
          ],
          recommendedActions: <String>[
            'Inspect iron, valves, choke manifold, plug catcher, separators, and restraints',
            'Check for leaks, washout, vibration, or damaged equipment',
            'Verify equipment pressure ratings',
            'Confirm restraints and supports are secure',
            'Do not tighten pressured connections',
            'Isolate and bleed pressure before repairs',
            'Stay clear of potential pressure-release paths',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Monitor well pressures during drillout',
          hazards: <String>[
            'Sudden pressure changes',
            'Pressure spikes',
            'Unexpected well response',
            'Gauge failure',
            'High-pressure release',
          ],
          recommendedActions: <String>[
            'Continuously monitor tubing and casing pressures',
            'Maintain communication with coil personnel',
            'Report abnormal pressure changes immediately',
            'Read gauges from a safe position',
            'Stay outside the line of fire',
            'Shut down or isolate equipment if pressure exceeds safe operating conditions',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Drill plugs and monitor plug progress',
          hazards: <String>[
            'Changing well conditions',
            'Pressure changes',
            'Plug debris',
            'Restricted flow',
            'Equipment upset',
            'Unexpected returns',
          ],
          recommendedActions: <String>[
            'Confirm current plug number and coil depth',
            'Maintain communication with coil personnel',
            'Monitor pressure and returns during drilling',
            'Track plug progress accurately',
            'Watch for changes in gas, sand, and fluid returns',
            'Communicate abnormal conditions immediately',
            'Stop operations when unsafe conditions develop',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Monitor gas and fluid returns',
          hazards: <String>[
            'Unexpected gas',
            'Flammable atmosphere',
            'H₂S or hazardous gas',
            'Fluid surges',
            'High flow rates',
            'Tank overflow',
          ],
          recommendedActions: <String>[
            'Monitor gas and fluid returns continuously',
            'Use gas detection where required',
            'Approach equipment from a safe position',
            'Monitor tank levels and available capacity',
            'Verify correct fluid routing',
            'Communicate significant changes in returns',
            'Keep ignition sources away from hydrocarbon areas',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Monitor and handle sand',
          hazards: <String>[
            'Abrasive sand',
            'Plugged equipment',
            'Washout',
            'High-pressure discharge',
            'Equipment vibration',
            'Flying debris',
          ],
          recommendedActions: <String>[
            'Monitor sand production and equipment continuously',
            'Dump sand as required',
            'Watch for abnormal pressure differential',
            'Inspect for washout, leaks, or excessive vibration',
            'Stand clear of dump and discharge paths',
            'Wear required eye, face, hand, and hearing protection',
            'Isolate and bleed pressure before clearing restrictions',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Operate plug catcher and related equipment',
          hazards: <String>[
            'Trapped pressure',
            'Plug debris',
            'Flying objects',
            'Heavy components',
            'Pinch points',
            'Unexpected fluid release',
          ],
          recommendedActions: <String>[
            'Verify equipment is isolated before opening',
            'Bleed all trapped pressure',
            'Confirm zero pressure before removing caps or opening equipment',
            'Stand in a safe position',
            'Use proper lifting and handling techniques',
            'Keep hands clear of pinch points',
            'Inspect equipment before returning it to service',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Adjust or change choke',
          hazards: <String>[
            'High pressure',
            'Stored energy',
            'Sudden flow changes',
            'Flying debris',
            'Equipment failure',
            'Pinch points',
          ],
          recommendedActions: <String>[
            'Confirm the intended choke size',
            'Communicate the choke change',
            'Stand outside the line of fire',
            'Follow approved choke-change procedures',
            'Isolate and bleed pressure when required',
            'Monitor pressures and returns after the change',
            'Stop work if equipment behaves abnormally',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Respond to leaks or equipment issues',
          hazards: <String>[
            'High-pressure release',
            'Hydrocarbon exposure',
            'Fire or explosion',
            'H₂S exposure',
            'Equipment failure',
            'Slips and falls',
          ],
          recommendedActions: <String>[
            'Do not tighten pressured connections',
            'Move personnel away from the affected area',
            'Notify affected crews immediately',
            'Isolate and bleed pressure before repairs',
            'Eliminate ignition sources when safe',
            'Use gas detection where required',
            'Document equipment issues and corrective actions',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Communicate shift status and handoff',
          hazards: <String>[
            'Missed operational changes',
            'Incorrect plug status',
            'Poor communication',
            'Incomplete pressure or equipment information',
          ],
          recommendedActions: <String>[
            'Record current plug number and coil depth',
            'Communicate current pressures and choke',
            'Report gas and sand conditions',
            'Report tank levels and fluid movement',
            'Identify equipment issues or repairs',
            'Document abnormal events',
            'Provide a clear shift change or update',
          ],
        ),
      ],
    ),
    JsaTemplateDefinition(
      id: 'rig_up',
      name: 'Rig Up',
      steps: <JsaTemplateStep>[
        JsaTemplateStep(
          basicJobStep: 'Conduct pre-job meeting and review rig-up plan',
          hazards: <String>[
            'Unclear equipment layout',
            'Simultaneous operations',
            'Poor communication',
            'Changing site conditions',
            'Unidentified hazards',
            'Personnel entering work areas',
          ],
          recommendedActions: <String>[
            'Review the rig-up layout and job scope',
            'Assign responsibilities',
            'Establish clear communication and hand signals',
            'Identify line-of-fire and exclusion areas',
            'Review emergency and medical plans',
            'Coordinate with all affected crews',
            'Stop work when conditions or instructions are unclear',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Inspect location and establish work area',
          hazards: <String>[
            'Uneven or unstable ground',
            'Mud, ice, or slippery surfaces',
            'Poor lighting',
            'Vehicle traffic',
            'Overhead hazards',
            'Underground or site hazards',
          ],
          recommendedActions: <String>[
            'Inspect ground and work surfaces',
            'Identify soft or unstable areas',
            'Establish equipment and vehicle routes',
            'Maintain adequate lighting',
            'Keep unauthorized personnel clear',
            'Identify overhead and site-specific hazards',
            'Maintain clear emergency access',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Spot trucks and equipment',
          hazards: <String>[
            'Moving vehicles',
            'Blind spots',
            'Backing equipment',
            'Personnel struck by equipment',
            'Equipment collisions',
            'Uneven ground',
          ],
          recommendedActions: <String>[
            'Use a designated spotter',
            'Establish clear hand signals or radio communication',
            'Maintain visual contact with the operator',
            'Stay out of blind spots',
            'Keep personnel clear of moving equipment',
            'Stop movement if visual or radio contact is lost',
            'Chock or secure equipment as required',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Unload and position equipment',
          hazards: <String>[
            'Suspended loads',
            'Dropped objects',
            'Swinging loads',
            'Pinch and crush points',
            'Rigging failure',
            'Heavy equipment',
          ],
          recommendedActions: <String>[
            'Inspect lifting equipment and rigging before use',
            'Use properly rated lifting equipment',
            'Never stand beneath a suspended load',
            'Stay clear of the load\'s travel path',
            'Use tag lines when appropriate',
            'Keep hands and feet clear of pinch points',
            'Use a designated signal person',
            'Stop the lift if conditions become unsafe',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Position and connect pressure-control equipment',
          hazards: <String>[
            'Heavy components',
            'Pinch points',
            'Strains and sprains',
            'Misaligned equipment',
            'Damaged connections',
            'Stored energy',
          ],
          recommendedActions: <String>[
            'Use mechanical lifting assistance when available',
            'Use proper body positioning and lifting techniques',
            'Keep hands clear while aligning equipment',
            'Inspect connections and sealing surfaces',
            'Verify correct equipment orientation',
            'Do not force damaged or misaligned connections',
            'Secure and support equipment properly',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Rig up iron, hoses, and flow lines',
          hazards: <String>[
            'Heavy iron',
            'Pinch and crush points',
            'Struck-by hazards',
            'Improper connections',
            'Line movement',
            'Trips and falls',
          ],
          recommendedActions: <String>[
            'Inspect iron and connections before installation',
            'Verify correct size and pressure rating',
            'Use proper lifting and handling methods',
            'Keep hands clear during alignment',
            'Route lines to minimize trip hazards',
            'Support iron and hoses properly',
            'Install restraints where required',
            'Verify all connections before pressure testing',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Install separators, tanks, and production equipment',
          hazards: <String>[
            'Heavy equipment',
            'Equipment movement',
            'Pinch points',
            'Incorrect flow routing',
            'Tank overflow potential',
            'Unstable equipment',
          ],
          recommendedActions: <String>[
            'Position equipment on stable ground',
            'Maintain adequate spacing and access',
            'Verify flow direction and equipment orientation',
            'Confirm tank and fluid routing',
            'Secure equipment as required',
            'Keep emergency and operating access clear',
            'Inspect all connections before startup',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Install restraints and secure equipment',
          hazards: <String>[
            'Line movement',
            'Restraint failure',
            'Pinch points',
            'Stored energy',
            'Improper anchor points',
          ],
          recommendedActions: <String>[
            'Install required restraints before pressure is introduced',
            'Inspect restraints for damage',
            'Use approved anchor points',
            'Keep personnel clear while tensioning restraints',
            'Verify restraints do not create additional hazards',
            'Replace damaged restraints',
            'Confirm restraint installation during final inspection',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Pressure test equipment',
          hazards: <String>[
            'High pressure',
            'Stored energy',
            'Equipment failure',
            'Flying debris',
            'High-pressure leaks',
            'Line movement',
          ],
          recommendedActions: <String>[
            'Conduct a pre-test equipment inspection',
            'Clear nonessential personnel from the test area',
            'Establish and maintain an exclusion zone',
            'Confirm all connections and restraints',
            'Increase pressure in a controlled manner',
            'Monitor equipment from a safe position',
            'Never approach or tighten leaking equipment while pressured',
            'Isolate and bleed pressure before repairs',
            'Confirm zero pressure before making adjustments',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Conduct final rig-up inspection and handoff',
          hazards: <String>[
            'Missed connections',
            'Incorrect valve alignment',
            'Unsecured equipment',
            'Trip hazards',
            'Poor communication',
          ],
          recommendedActions: <String>[
            'Walk the complete flow path',
            'Verify valve alignment and flow direction',
            'Inspect connections, supports, and restraints',
            'Confirm tanks and dump lines are properly routed',
            'Remove tools and unnecessary materials',
            'Correct trip and access hazards',
            'Communicate equipment status and outstanding issues',
            'Confirm the rig up is ready before introducing flow',
          ],
        ),
      ],
    ),
    JsaTemplateDefinition(
      id: 'rig_down',
      name: 'Rig Down',
      steps: <JsaTemplateStep>[
        JsaTemplateStep(
          basicJobStep: 'Conduct pre-job meeting and review rig-down plan',
          hazards: <String>[
            'Unclear responsibilities',
            'Simultaneous operations',
            'Changing site conditions',
            'Poor communication',
            'Personnel entering work areas',
            'Unidentified stored energy',
          ],
          recommendedActions: <String>[
            'Review the rig-down sequence and job scope',
            'Assign responsibilities',
            'Establish clear communication and hand signals',
            'Identify line-of-fire and exclusion areas',
            'Coordinate with all affected crews',
            'Review emergency and medical plans',
            'Stop work if conditions or instructions are unclear',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Shut down and isolate production equipment',
          hazards: <String>[
            'High pressure',
            'Stored energy',
            'Unexpected flow',
            'Incorrect valve operation',
            'Equipment movement',
            'Hydrocarbon release',
          ],
          recommendedActions: <String>[
            'Communicate before shutting down equipment',
            'Follow the approved shutdown sequence',
            'Verify correct valve positions',
            'Isolate equipment from all pressure sources',
            'Monitor pressures during shutdown',
            'Stay outside the line of fire',
            'Do not begin disassembly until isolation is confirmed',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Bleed pressure and verify zero energy',
          hazards: <String>[
            'Trapped pressure',
            'Stored energy',
            'Plugged bleed points',
            'Unexpected gas or fluid release',
            'Flying debris',
            'H₂S or hazardous gas',
          ],
          recommendedActions: <String>[
            'Bleed pressure through an approved path',
            'Stand in a safe position while bleeding pressure',
            'Monitor all available pressure gauges',
            'Verify zero pressure before breaking connections',
            'Consider pressure trapped between valves',
            'Verify bleed points are not plugged',
            'Use gas detection where required',
            'Never assume equipment is depressurized',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Drain and control residual fluids',
          hazards: <String>[
            'Hydrocarbon exposure',
            'Hot fluids',
            'Chemical exposure',
            'Unexpected fluid release',
            'Slips and falls',
            'Environmental release',
          ],
          recommendedActions: <String>[
            'Drain equipment into approved containment',
            'Verify hoses and drain paths are secure',
            'Wear required PPE',
            'Open drains slowly',
            'Maintain control of residual fluids',
            'Clean or barricade spills promptly',
            'Report releases according to site procedures',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Break iron and pressure connections',
          hazards: <String>[
            'Trapped pressure',
            'Heavy iron',
            'Pinch and crush points',
            'Unexpected fluid release',
            'Struck-by hazards',
            'Sharp edges',
          ],
          recommendedActions: <String>[
            'Confirm zero pressure before loosening any connection',
            'Stand outside the potential release path',
            'Break connections slowly and cautiously',
            'Keep hands and feet clear of pinch points',
            'Use proper tools',
            'Use mechanical assistance for heavy components',
            'Stop immediately if pressure or unexpected fluid is encountered',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Remove restraints and supports',
          hazards: <String>[
            'Line or equipment movement',
            'Stored tension',
            'Pinch points',
            'Struck-by hazards',
            'Heavy components',
          ],
          recommendedActions: <String>[
            'Confirm equipment is depressurized before removing restraints',
            'Identify stored tension before disconnecting',
            'Maintain safe body positioning',
            'Keep personnel clear of potential movement',
            'Remove restraints in a controlled sequence',
            'Inspect restraints before storage',
            'Do not stand in the path of tensioned equipment',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Disconnect and remove production equipment',
          hazards: <String>[
            'Heavy components',
            'Pinch and crush points',
            'Residual fluids',
            'Equipment movement',
            'Strains and sprains',
            'Dropped objects',
          ],
          recommendedActions: <String>[
            'Use mechanical lifting assistance when available',
            'Inspect lifting points before use',
            'Maintain clear communication',
            'Keep hands and feet clear',
            'Control equipment movement',
            'Use proper lifting techniques',
            'Drain and cap equipment as required',
            'Maintain good housekeeping during disassembly',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Load equipment and iron',
          hazards: <String>[
            'Suspended loads',
            'Dropped objects',
            'Swinging loads',
            'Moving vehicles',
            'Pinch points',
            'Improperly secured loads',
          ],
          recommendedActions: <String>[
            'Inspect rigging and lifting equipment',
            'Use properly rated lifting equipment',
            'Never stand beneath suspended loads',
            'Stay clear of load travel paths',
            'Use tag lines when appropriate',
            'Use a designated signal person',
            'Secure equipment and iron for transport',
            'Verify load placement and weight distribution',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Inspect and clean the work location',
          hazards: <String>[
            'Leftover equipment or materials',
            'Fluid spills',
            'Trip hazards',
            'Sharp objects',
            'Environmental hazards',
            'Vehicle traffic',
          ],
          recommendedActions: <String>[
            'Walk the entire work area',
            'Remove tools, trash, and unused materials',
            'Clean or report fluid spills',
            'Inspect for leaks or environmental issues',
            'Remove trip hazards',
            'Maintain awareness of moving vehicles',
            'Confirm all company equipment is accounted for',
          ],
        ),
        JsaTemplateStep(
          basicJobStep: 'Complete final handoff and documentation',
          hazards: <String>[
            'Missing equipment',
            'Unreported damage',
            'Poor communication',
            'Incomplete documentation',
            'Unresolved site hazards',
          ],
          recommendedActions: <String>[
            'Verify equipment inventory',
            'Report damaged or missing equipment',
            'Document spills, leaks, or abnormal events',
            'Communicate outstanding site conditions',
            'Confirm the work area is left in acceptable condition',
            'Complete required job documentation',
            'Provide a clear final handoff',
          ],
        ),
      ],
    ),
  ];

  static JsaTemplateDefinition? byId(String id) {
    final normalized = id.trim().toLowerCase();
    for (final template in all) {
      if (template.id == normalized) {
        return template;
      }
    }
    return null;
  }

  static JsaTemplateDefinition? byName(String name) {
    final normalized = name.trim().toLowerCase();
    for (final template in all) {
      if (template.name.toLowerCase() == normalized) {
        return template;
      }
    }
    return null;
  }
}
