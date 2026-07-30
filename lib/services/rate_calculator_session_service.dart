import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RateCalculatorSessionLogEntry {
  const RateCalculatorSessionLogEntry({
    required this.timestampMs,
    required this.rateValue,
    required this.rateUnit,
    required this.selected,
  });

  final int timestampMs;
  final double rateValue;
  final String rateUnit;
  final bool selected;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestampMs': timestampMs,
      'rateValue': rateValue,
      'rateUnit': rateUnit,
      'selected': selected,
    };
  }

  factory RateCalculatorSessionLogEntry.fromJson(Map<String, dynamic> map) {
    return RateCalculatorSessionLogEntry(
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
      rateValue: (map['rateValue'] as num?)?.toDouble() ?? 0,
      rateUnit: (map['rateUnit'] as String? ?? '').trim(),
      selected: map['selected'] as bool? ?? true,
    );
  }
}

class RateCalculatorSession {
  const RateCalculatorSession({
    required this.calculatorId,
    required this.calculatorTitle,
    required this.chartId,
    required this.usesChart,
    required this.startGauge,
    required this.endGauge,
    required this.minutes,
    required this.factor,
    required this.rateDisplayUnit,
    required this.rateLogEnabled,
    required this.rateLogExpanded,
    required this.bblPerMin,
    required this.bblPerHr,
    required this.bblPerDay,
    required this.error,
    required this.timerFinished,
    required this.remainingSeconds,
    required this.thirtySecondAlertShown,
    required this.timerStartedAtMs,
    required this.timerEndsAtMs,
    required this.timerDurationSeconds,
    required this.rateLogEntries,
    required this.updatedAtMs,
  });

  final String calculatorId;
  final String calculatorTitle;
  final String chartId;
  final bool usesChart;
  final String startGauge;
  final String endGauge;
  final String minutes;
  final String factor;
  final String rateDisplayUnit;
  final bool rateLogEnabled;
  final bool rateLogExpanded;
  final double? bblPerMin;
  final double? bblPerHr;
  final double? bblPerDay;
  final String? error;
  final bool timerFinished;
  final int remainingSeconds;
  final bool thirtySecondAlertShown;
  final int? timerStartedAtMs;
  final int? timerEndsAtMs;
  final int? timerDurationSeconds;
  final List<RateCalculatorSessionLogEntry> rateLogEntries;
  final int updatedAtMs;

  bool get hasUserData {
    return startGauge.trim().isNotEmpty ||
        endGauge.trim().isNotEmpty ||
        bblPerMin != null ||
        bblPerHr != null ||
        bblPerDay != null ||
        rateLogEntries.isNotEmpty ||
        rateLogEnabled ||
        rateLogExpanded ||
        (error?.trim().isNotEmpty ?? false) ||
        timerFinished ||
        timerStartedAtMs != null ||
        timerEndsAtMs != null ||
        remainingSeconds > 0;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'calculatorId': calculatorId,
      'calculatorTitle': calculatorTitle,
      'chartId': chartId,
      'usesChart': usesChart,
      'startGauge': startGauge,
      'endGauge': endGauge,
      'minutes': minutes,
      'factor': factor,
      'rateDisplayUnit': rateDisplayUnit,
      'rateLogEnabled': rateLogEnabled,
      'rateLogExpanded': rateLogExpanded,
      'bblPerMin': bblPerMin,
      'bblPerHr': bblPerHr,
      'bblPerDay': bblPerDay,
      'error': error,
      'timerFinished': timerFinished,
      'remainingSeconds': remainingSeconds,
      'thirtySecondAlertShown': thirtySecondAlertShown,
      'timerStartedAtMs': timerStartedAtMs,
      'timerEndsAtMs': timerEndsAtMs,
      'timerDurationSeconds': timerDurationSeconds,
      'rateLogEntries':
          rateLogEntries.map((entry) => entry.toJson()).toList(growable: false),
      'updatedAtMs': updatedAtMs,
    };
  }

  factory RateCalculatorSession.fromJson(Map<String, dynamic> map) {
    double? asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return null;
    }

    List<RateCalculatorSessionLogEntry> parseRateLogEntries(dynamic raw) {
      if (raw is! List) return const <RateCalculatorSessionLogEntry>[];
      final entries = <RateCalculatorSessionLogEntry>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final mapped = Map<String, dynamic>.from(item);
        final entry = RateCalculatorSessionLogEntry.fromJson(mapped);
        if (entry.timestampMs <= 0 ||
            entry.rateUnit.isEmpty ||
            !entry.rateValue.isFinite) {
          continue;
        }
        entries.add(entry);
      }
      entries.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      return entries;
    }

    return RateCalculatorSession(
      calculatorId: (map['calculatorId'] as String? ?? '').trim(),
      calculatorTitle: (map['calculatorTitle'] as String? ?? '').trim(),
      chartId: (map['chartId'] as String? ?? '').trim(),
      usesChart: map['usesChart'] as bool? ?? true,
      startGauge: (map['startGauge'] as String? ?? '').trim(),
      endGauge: (map['endGauge'] as String? ?? '').trim(),
      minutes: (map['minutes'] as String? ?? '').trim(),
      factor: (map['factor'] as String? ?? '').trim(),
      rateDisplayUnit: (map['rateDisplayUnit'] as String? ?? 'bbl_min').trim(),
      rateLogEnabled: map['rateLogEnabled'] as bool? ?? false,
      rateLogExpanded: map['rateLogExpanded'] as bool? ?? false,
      bblPerMin: asDouble(map['bblPerMin']),
      bblPerHr: asDouble(map['bblPerHr']),
      bblPerDay: asDouble(map['bblPerDay']),
      error: (map['error'] as String?)?.trim(),
      timerFinished: map['timerFinished'] as bool? ?? false,
      remainingSeconds: (map['remainingSeconds'] as num?)?.toInt() ?? 0,
      thirtySecondAlertShown: map['thirtySecondAlertShown'] as bool? ?? false,
      timerStartedAtMs: (map['timerStartedAtMs'] as num?)?.toInt(),
      timerEndsAtMs: (map['timerEndsAtMs'] as num?)?.toInt(),
      timerDurationSeconds: (map['timerDurationSeconds'] as num?)?.toInt(),
      rateLogEntries: parseRateLogEntries(map['rateLogEntries']),
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class RateCalculatorSessionService {
  RateCalculatorSessionService._();

  static final RateCalculatorSessionService instance =
      RateCalculatorSessionService._();

  static const _sessionsKey = 'wellwerks_rate_calculator_sessions_v1';
  static const _activeSessionKey = 'wellwerks_rate_calculator_active_v1';

  bool _initialized = false;
  String _activeCalculatorId = '';
  final Map<String, RateCalculatorSession> _sessionsByCalculatorId =
      <String, RateCalculatorSession>{};

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_sessionsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            if (value is Map) {
              final session = RateCalculatorSession.fromJson(
                  Map<String, dynamic>.from(value));
              if (session.calculatorId.isNotEmpty) {
                _sessionsByCalculatorId[key] = session;
              }
            }
          });
        }
      } catch (_) {
        // Ignore malformed persisted session data.
      }
    }

    _activeCalculatorId = (prefs.getString(_activeSessionKey) ?? '').trim();
    _initialized = true;
  }

  RateCalculatorSession? sessionForCalculator(String calculatorId) {
    final key = calculatorId.trim();
    if (key.isEmpty) return null;
    return _sessionsByCalculatorId[key];
  }

  String get activeCalculatorId => _activeCalculatorId;

  Future<void> saveSession(
    RateCalculatorSession session, {
    bool setActive = false,
  }) async {
    await ensureInitialized();
    final key = session.calculatorId.trim();
    if (key.isEmpty) return;
    _sessionsByCalculatorId[key] = session;
    if (setActive) {
      _activeCalculatorId = key;
    }
    await _flush();
  }

  Future<void> setActiveCalculator(String calculatorId) async {
    await ensureInitialized();
    _activeCalculatorId = calculatorId.trim();
    await _flush();
  }

  Future<void> clearActiveCalculator() async {
    await ensureInitialized();
    _activeCalculatorId = '';
    await _flush();
  }

  Future<void> clearSession(String calculatorId) async {
    await ensureInitialized();
    final key = calculatorId.trim();
    if (key.isEmpty) return;
    _sessionsByCalculatorId.remove(key);
    if (_activeCalculatorId == key) {
      _activeCalculatorId = '';
    }
    await _flush();
  }

  Future<void> _flush() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{};
    _sessionsByCalculatorId.forEach((key, session) {
      payload[key] = session.toJson();
    });
    await prefs.setString(_sessionsKey, jsonEncode(payload));
    await prefs.setString(_activeSessionKey, _activeCalculatorId);
  }

  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
    _activeCalculatorId = '';
    _sessionsByCalculatorId.clear();
  }
}
