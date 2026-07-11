import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RateTimerState {
  const RateTimerState({
    required this.instanceId,
    required this.calculatorId,
    required this.calculatorTitle,
    required this.wellOrJob,
    required this.durationSeconds,
    required this.startedAtMs,
    required this.endsAtMs,
    required this.warningNotificationId,
    required this.completeNotificationId,
  });

  final String instanceId;
  final String calculatorId;
  final String calculatorTitle;
  final String wellOrJob;
  final int durationSeconds;
  final int startedAtMs;
  final int endsAtMs;
  final int warningNotificationId;
  final int completeNotificationId;

  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch(startedAtMs);
  DateTime get endsAt => DateTime.fromMillisecondsSinceEpoch(endsAtMs);

  int remainingSecondsAt(DateTime now) {
    final seconds = endsAt.difference(now).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  bool isRunningAt(DateTime now) => remainingSecondsAt(now) > 0;

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'calculatorId': calculatorId,
        'calculatorTitle': calculatorTitle,
        'wellOrJob': wellOrJob,
        'durationSeconds': durationSeconds,
        'startedAtMs': startedAtMs,
        'endsAtMs': endsAtMs,
        'warningNotificationId': warningNotificationId,
        'completeNotificationId': completeNotificationId,
      };

  factory RateTimerState.fromJson(Map<String, dynamic> json) {
    return RateTimerState(
      instanceId: (json['instanceId'] as String? ?? '').trim(),
      calculatorId: (json['calculatorId'] as String? ?? '').trim(),
      calculatorTitle: (json['calculatorTitle'] as String? ?? '').trim(),
      wellOrJob: (json['wellOrJob'] as String? ?? '').trim(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      startedAtMs: (json['startedAtMs'] as num?)?.toInt() ?? 0,
      endsAtMs: (json['endsAtMs'] as num?)?.toInt() ?? 0,
      warningNotificationId:
          (json['warningNotificationId'] as num?)?.toInt() ?? 0,
      completeNotificationId:
          (json['completeNotificationId'] as num?)?.toInt() ?? 0,
    );
  }

  RateTimerState copyWith({
    String? instanceId,
    String? calculatorId,
    String? calculatorTitle,
    String? wellOrJob,
    int? durationSeconds,
    int? startedAtMs,
    int? endsAtMs,
    int? warningNotificationId,
    int? completeNotificationId,
  }) {
    return RateTimerState(
      instanceId: instanceId ?? this.instanceId,
      calculatorId: calculatorId ?? this.calculatorId,
      calculatorTitle: calculatorTitle ?? this.calculatorTitle,
      wellOrJob: wellOrJob ?? this.wellOrJob,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      startedAtMs: startedAtMs ?? this.startedAtMs,
      endsAtMs: endsAtMs ?? this.endsAtMs,
      warningNotificationId:
          warningNotificationId ?? this.warningNotificationId,
      completeNotificationId:
          completeNotificationId ?? this.completeNotificationId,
    );
  }
}

enum RateTimerPendingActionType {
  openCalculator,
  stopTimer,
  restartTimer,
}

class RateTimerPendingAction {
  const RateTimerPendingAction({
    required this.type,
    required this.payload,
  });

  final RateTimerPendingActionType type;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'payload': payload,
      };

  factory RateTimerPendingAction.fromJson(Map<String, dynamic> json) {
    final typeRaw = (json['type'] as String? ?? '').trim();
    final payload = Map<String, dynamic>.from(
      (json['payload'] as Map?) ?? const <String, dynamic>{},
    );
    final type = RateTimerPendingActionType.values.firstWhere(
      (item) => item.name == typeRaw,
      orElse: () => RateTimerPendingActionType.openCalculator,
    );
    return RateTimerPendingAction(type: type, payload: payload);
  }
}

class RateTimerService {
  static const _activeTimerKey = 'wellwerks_rate_timer_active_v1';
  static const _pendingActionKey = 'wellwerks_rate_timer_pending_action_v1';

  Future<RateTimerState?> loadActiveTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeTimerKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final state =
          RateTimerState.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
      if (state.instanceId.isEmpty ||
          state.calculatorId.isEmpty ||
          state.durationSeconds <= 0 ||
          state.startsAtInvalid ||
          state.endsAtMs <= state.startedAtMs) {
        await prefs.remove(_activeTimerKey);
        return null;
      }
      return state;
    } catch (_) {
      await prefs.remove(_activeTimerKey);
      return null;
    }
  }

  Future<void> saveActiveTimer(RateTimerState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeTimerKey, jsonEncode(state.toJson()));
  }

  Future<void> clearActiveTimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeTimerKey);
  }

  Future<RateTimerPendingAction?> consumePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingActionKey);
    if (raw == null || raw.isEmpty) return null;
    await prefs.remove(_pendingActionKey);
    try {
      return RateTimerPendingAction.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setPendingAction(RateTimerPendingAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingActionKey, jsonEncode(action.toJson()));
  }

  Future<RateTimerState> createState({
    required String calculatorId,
    required String calculatorTitle,
    required String wellOrJob,
    required int durationSeconds,
  }) async {
    final now = DateTime.now();
    final startedAtMs = now.millisecondsSinceEpoch;
    final endsAtMs =
        now.add(Duration(seconds: durationSeconds)).millisecondsSinceEpoch;
    final seed = startedAtMs % 100000;
    final warningId = seed + 1000;
    final completeId = seed + 2000;
    return RateTimerState(
      instanceId: '$startedAtMs:$calculatorId',
      calculatorId: calculatorId,
      calculatorTitle: calculatorTitle,
      wellOrJob: wellOrJob,
      durationSeconds: durationSeconds,
      startedAtMs: startedAtMs,
      endsAtMs: endsAtMs,
      warningNotificationId: warningId,
      completeNotificationId: completeId,
    );
  }
}

extension on RateTimerState {
  bool get startsAtInvalid => startedAtMs <= 0;
}
