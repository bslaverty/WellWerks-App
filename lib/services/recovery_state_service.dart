import 'package:shared_preferences/shared_preferences.dart';

class RecoveryModules {
  static const quickRound = 'quick_round';
  static const productionReport = 'production_report';
  static const textUpdate = 'text_update';
  static const productionShiftChange = 'production_shift_change';
  static const jsa = 'jsa';
  static const layoutDesigner = 'layout_designer';
  static const rigUpInventory = 'rig_up_inventory';
  static const rigUpHistory = 'rig_up_history';
  static const history = 'history';
}

class RecoveryStateSnapshot {
  const RecoveryStateSnapshot({
    required this.lastActiveJobId,
    required this.lastModule,
  });

  final String lastActiveJobId;
  final String lastModule;
}

class RecoveryStateService {
  static const _lastModuleKey = 'wellwerks_recovery_last_module_v1';

  Future<void> saveLastModule(String module) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastModuleKey, module.trim());
  }

  Future<String> loadLastModule() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastModuleKey) ?? '';
  }

  Future<RecoveryStateSnapshot> loadSnapshot({
    required String lastActiveJobId,
  }) async {
    final lastModule = await loadLastModule();
    return RecoveryStateSnapshot(
      lastActiveJobId: lastActiveJobId,
      lastModule: lastModule,
    );
  }

  Future<void> clearLastModule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastModuleKey);
  }
}
