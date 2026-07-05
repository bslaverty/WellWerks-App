import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/production_shift.dart';

class ProductionMath {
  static double parse(String value) => double.tryParse(value.trim()) ?? 0;

  static double tankFactor(String value) {
    final parsed = parse(value);
    return parsed <= 0 ? 1.67 : parsed;
  }

  static double totalTankBbl(
    List<ProductionTank> tanks,
    List<String> gauges,
  ) {
    var total = 0.0;
    for (var i = 0; i < tanks.length; i++) {
      final gauge = i < gauges.length ? parse(gauges[i]) : 0;
      total += gauge * tankFactor(tanks[i].bblPerInch);
    }
    return total;
  }

  static ProductionReportRow? previousSavedRow(
    List<ProductionReportRow> rows,
    int hourIndex,
  ) {
    final previous = rows.where((row) => row.hourIndex < hourIndex).toList()
      ..sort((a, b) => a.hourIndex.compareTo(b.hourIndex));
    if (previous.isEmpty) return null;
    return previous.last;
  }

  static double waterProduction({
    required double currentWaterBbl,
    required double previousWaterBbl,
    required double waterHauled,
    required double waterPumped,
    required double preRoundWaterHauled,
    required double preRoundWaterPumped,
    required bool isFirstHour,
  }) {
    return currentWaterBbl -
        previousWaterBbl +
        waterHauled +
        waterPumped +
        (isFirstHour ? preRoundWaterHauled : 0) +
        (isFirstHour ? preRoundWaterPumped : 0);
  }

  static double oilProduction({
    required double currentOilBbl,
    required double previousOilBbl,
    required double oilHauled,
    required double oilPumped,
    required double preRoundOilHauled,
    required double preRoundOilPumped,
    required bool isFirstHour,
  }) {
    return currentOilBbl -
        previousOilBbl +
        oilHauled +
        oilPumped +
        (isFirstHour ? preRoundOilHauled : 0) +
        (isFirstHour ? preRoundOilPumped : 0);
  }

  static double hourlyGas({
    required double currentGasAccum,
    required double previousGasAccum,
  }) {
    return currentGasAccum - previousGasAccum;
  }

  static double gas24Hour(double hourlyGas) => hourlyGas * 24;
}

class ProductionShiftService {
  static const _activeKey = 'wellwerks_production_active_shift_v2';
  static const _historyKey = 'wellwerks_production_history_v2';

  Future<ProductionShift> loadActiveShift() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeKey);
    if (raw == null || raw.isEmpty) {
      return ProductionShift.empty();
    }

    try {
      return ProductionShift.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return ProductionShift.empty();
    }
  }

  Future<void> saveActiveShift(ProductionShift shift) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, jsonEncode(shift.toJson()));
  }

  Future<void> clearActiveShift() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
  }

  Future<List<ProductionShift>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) =>
              ProductionShift.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> archiveActiveShift() async {
    final active = await loadActiveShift();
    if (_isEmptyShift(active)) return;
    final history = await loadHistory();
    final archived = active.copyWith(updatedAt: DateTime.now());
    history.insert(0, archived);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(history.take(60).map((item) => item.toJson()).toList()),
    );
  }

  Future<File> exportReportCsv({
    required String fileName,
    required String csv,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csv);
    return file;
  }

  bool _isEmptyShift(ProductionShift shift) {
    final header = shift.header;
    final inventory = shift.inventory;
    final hasHeader = [
      header.company,
      header.pad,
      header.date,
      header.chokeType,
    ].any((value) => value.trim().isNotEmpty);
    final hasInventory = inventory.startingGasAccum.trim().isNotEmpty ||
        inventory.waterTanks.any((tank) =>
            tank.name.trim().isNotEmpty ||
            tank.gauge.trim().isNotEmpty ||
            tank.bblPerInch.trim().isNotEmpty) ||
        inventory.oilTanks.any((tank) =>
            tank.name.trim().isNotEmpty ||
            tank.gauge.trim().isNotEmpty ||
            tank.bblPerInch.trim().isNotEmpty);
    return !hasHeader &&
        !hasInventory &&
        shift.hourlyChecks.isEmpty &&
        shift.savedRows.isEmpty;
  }
}
