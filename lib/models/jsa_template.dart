class JsaTemplateDefinition {
  const JsaTemplateDefinition({
    required this.id,
    required this.name,
    this.basicJobSteps = const <String>[],
    this.hazards = const <String>[],
    this.recommendedActions = const <String>[],
    this.requiredPpe = const <String>[],
    this.specialInstructions = const <String>[],
  });

  final String id;
  final String name;
  final List<String> basicJobSteps;
  final List<String> hazards;
  final List<String> recommendedActions;

  // Reserved for future builds so we can extend without breaking templates.
  final List<String> requiredPpe;
  final List<String> specialInstructions;
}

class JsaBuiltInTemplates {
  static const List<JsaTemplateDefinition> all = <JsaTemplateDefinition>[
    JsaTemplateDefinition(id: 'production', name: 'Production'),
    JsaTemplateDefinition(
      id: 'production_startup',
      name: 'Production Startup',
    ),
    JsaTemplateDefinition(id: 'drillout', name: 'Drillout'),
    JsaTemplateDefinition(id: 'rig_up', name: 'Rig Up'),
    JsaTemplateDefinition(id: 'rig_down', name: 'Rig Down'),
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
