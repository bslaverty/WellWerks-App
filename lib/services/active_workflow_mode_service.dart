import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActiveWorkflowMode {
  production,
  drillout,
  cleanout,
}

class ActiveWorkflowModeService {
  static const _prefsKey = 'wellwerks_active_workflow_mode_v1';
  static final ActiveWorkflowModeService instance =
      ActiveWorkflowModeService._();

  ActiveWorkflowModeService._();

  final ValueNotifier<ActiveWorkflowMode> mode =
      ValueNotifier<ActiveWorkflowMode>(ActiveWorkflowMode.production);
  bool _loaded = false;

  Future<ActiveWorkflowMode> ensureLoaded() async {
    if (_loaded) return mode.value;
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(_prefsKey) ?? '').trim().toLowerCase();
    mode.value = _parse(raw);
    _loaded = true;
    return mode.value;
  }

  Future<void> setMode(ActiveWorkflowMode next) async {
    await ensureLoaded();
    mode.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(next));
  }

  ActiveWorkflowMode _parse(String raw) {
    switch (raw) {
      case 'drillout':
        return ActiveWorkflowMode.drillout;
      case 'cleanout':
        return ActiveWorkflowMode.cleanout;
      case 'production':
      default:
        return ActiveWorkflowMode.production;
    }
  }

  String _encode(ActiveWorkflowMode mode) {
    switch (mode) {
      case ActiveWorkflowMode.drillout:
        return 'drillout';
      case ActiveWorkflowMode.cleanout:
        return 'cleanout';
      case ActiveWorkflowMode.production:
        return 'production';
    }
  }

  static String labelFor(ActiveWorkflowMode mode) {
    switch (mode) {
      case ActiveWorkflowMode.drillout:
        return 'Drillout';
      case ActiveWorkflowMode.cleanout:
        return 'Cleanout';
      case ActiveWorkflowMode.production:
        return 'Production';
    }
  }
}
