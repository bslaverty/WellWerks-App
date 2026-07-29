import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/operations_log_entry.dart';
import 'app_settings_service.dart';
import 'rate_timer_notification_service.dart';

class StsReminderChoice {
  static const useDefault = 'useDefault';
  static const none = 'none';

  static String explicit(int minutes) => 'minutes:$minutes';
}

class StsReminderOption {
  const StsReminderOption({
    required this.choice,
    required this.label,
    this.minutes,
  });

  final String choice;
  final String label;
  final int? minutes;
}

class StsReminderSyncResult {
  const StsReminderSyncResult({
    required this.entry,
    this.userMessage,
    this.needsLateDecision = false,
    this.recommendedLeadMinutes,
  });

  final OperationsLogEntry entry;
  final String? userMessage;
  final bool needsLateDecision;
  final int? recommendedLeadMinutes;
}

class OperationsStsReminderService {
  static const List<int> allowedLeadMinutes = <int>[5, 10, 15, 20, 30, 45, 60];
  static const _registryKey = 'wellwerks_estimated_sts_registry_v1';

  final AppSettingsService _settingsService;
  final RateTimerNotificationService _notificationService;

  OperationsStsReminderService({
    AppSettingsService? settingsService,
    RateTimerNotificationService? notificationService,
  })  : _settingsService = settingsService ?? AppSettingsService(),
        _notificationService =
            notificationService ?? RateTimerNotificationService.instance;

  Future<AppSettingsData> loadSettings() => _settingsService.load();

  List<StsReminderOption> options({required int defaultLeadMinutes}) {
    return <StsReminderOption>[
      StsReminderOption(
        choice: StsReminderChoice.useDefault,
        label: 'Use default - ${leadTimeLabel(defaultLeadMinutes)} before',
      ),
      const StsReminderOption(
        choice: StsReminderChoice.none,
        label: 'No reminder',
      ),
      for (final minutes in allowedLeadMinutes)
        StsReminderOption(
          choice: StsReminderChoice.explicit(minutes),
          minutes: minutes,
          label: '${leadTimeLabel(minutes)} before',
        ),
    ];
  }

  String normalizeChoice(String raw, {required int defaultLeadMinutes}) {
    final trimmed = raw.trim();
    if (trimmed == StsReminderChoice.useDefault ||
        trimmed == StsReminderChoice.none) {
      return trimmed;
    }
    final explicit = _explicitMinutes(trimmed);
    if (explicit != null && allowedLeadMinutes.contains(explicit)) {
      return StsReminderChoice.explicit(explicit);
    }
    if (allowedLeadMinutes.contains(defaultLeadMinutes)) {
      return StsReminderChoice.useDefault;
    }
    return StsReminderChoice.explicit(10);
  }

  int? resolveLeadMinutes(String choice, {required int defaultLeadMinutes}) {
    if (choice == StsReminderChoice.none) return null;
    if (choice == StsReminderChoice.useDefault) return defaultLeadMinutes;
    final explicit = _explicitMinutes(choice);
    if (explicit != null && allowedLeadMinutes.contains(explicit)) {
      return explicit;
    }
    return defaultLeadMinutes;
  }

  String optionLabel(String choice, {required int defaultLeadMinutes}) {
    final normalized = normalizeChoice(
      choice,
      defaultLeadMinutes: defaultLeadMinutes,
    );
    return options(defaultLeadMinutes: defaultLeadMinutes)
        .firstWhere(
          (item) => item.choice == normalized,
          orElse: () => StsReminderOption(
            choice: StsReminderChoice.useDefault,
            label: 'Use default - ${leadTimeLabel(defaultLeadMinutes)} before',
          ),
        )
        .label;
  }

  String leadTimeLabel(int minutes) {
    if (minutes == 60) return '1 hour';
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return '$hours hours';
    }
    return '$minutes minutes';
  }

  Future<StsReminderSyncResult> syncForSavedEntry({
    required OperationsLogEntry entry,
    required bool remindersEnabled,
    required int defaultLeadMinutes,
    required bool permissionGranted,
  }) async {
    final now = DateTime.now();

    final reminderChoice = normalizeChoice(
      entry.estimatedStsReminderChoice,
      defaultLeadMinutes: defaultLeadMinutes,
    );

    var next = entry.copyWith(
      estimatedStsReminderChoice: reminderChoice,
      estimatedStsReminderResolvedAt: now,
    );

    final notificationId = next.estimatedStsNotificationId ??
        _notificationService.notificationIdForSweep(
          next.sweepId.trim().isEmpty ? next.entryId : next.sweepId,
        );

    if (next.estimatedSts == null) {
      await _notificationService.cancelEstimatedStsReminder(notificationId);
      next = next.copyWith(
        estimatedStsNotificationId: notificationId,
        estimatedStsNotificationStatus: 'notScheduled',
        estimatedStsNotificationScheduledAt: null,
        estimatedStsCancellationReason: 'estimatedStsCleared',
      );
      await _removeRegistry(next.sweepId);
      return StsReminderSyncResult(entry: next);
    }

    if (!remindersEnabled) {
      next = next.copyWith(
        estimatedStsNotificationId: notificationId,
        estimatedStsNotificationStatus: 'notScheduled',
        estimatedStsNotificationScheduledAt: null,
      );
      await _upsertRegistry(next, notificationId: notificationId);
      return StsReminderSyncResult(entry: next);
    }

    final leadMinutes = resolveLeadMinutes(
      reminderChoice,
      defaultLeadMinutes: defaultLeadMinutes,
    );
    if (leadMinutes == null) {
      await _notificationService.cancelEstimatedStsReminder(notificationId);
      next = next.copyWith(
        estimatedStsReminderLeadMinutes: null,
        estimatedStsNotificationId: notificationId,
        estimatedStsNotificationStatus: 'noReminder',
        estimatedStsNotificationScheduledAt: null,
        estimatedStsCancellationReason: 'noReminder',
      );
      await _upsertRegistry(next, notificationId: notificationId);
      return StsReminderSyncResult(entry: next);
    }

    if (!permissionGranted) {
      next = next.copyWith(
        estimatedStsReminderLeadMinutes: leadMinutes,
        estimatedStsNotificationId: notificationId,
        estimatedStsNotificationStatus: 'permissionDenied',
        estimatedStsNotificationScheduledAt: null,
      );
      await _upsertRegistry(next, notificationId: notificationId);
      return StsReminderSyncResult(
        entry: next,
        userMessage: 'Estimated STS saved, but notifications are disabled.',
      );
    }

    final estimated = next.estimatedSts!;
    if (!estimated.isAfter(now)) {
      await _notificationService.cancelEstimatedStsReminder(notificationId);
      next = next.copyWith(
        estimatedStsReminderLeadMinutes: leadMinutes,
        estimatedStsNotificationId: notificationId,
        estimatedStsNotificationStatus: 'estimatedStsPassed',
        estimatedStsNotificationScheduledAt: null,
      );
      await _upsertRegistry(next, notificationId: notificationId);
      return StsReminderSyncResult(
        entry: next,
        userMessage:
            'Estimated STS is in the past, so no reminder was scheduled.',
      );
    }

    final scheduledAt = estimated.subtract(Duration(minutes: leadMinutes));
    if (!scheduledAt.isAfter(now)) {
      await _notificationService.cancelEstimatedStsReminder(notificationId);
      next = next.copyWith(
        estimatedStsReminderLeadMinutes: leadMinutes,
        estimatedStsNotificationId: notificationId,
        estimatedStsNotificationStatus: 'reminderTimePassed',
        estimatedStsNotificationScheduledAt: null,
      );
      await _upsertRegistry(next, notificationId: notificationId);
      return StsReminderSyncResult(
        entry: next,
        userMessage: 'The selected reminder time has already passed.',
        needsLateDecision: true,
        recommendedLeadMinutes: leadMinutes,
      );
    }

    await _notificationService.scheduleEstimatedStsReminder(
      notificationId: notificationId,
      scheduledAt: scheduledAt,
      wellName: next.wellName,
      leadMinutes: leadMinutes,
      sweepId: next.sweepId,
      entryId: next.entryId,
      persistentJobId: next.persistentJobId,
      workflow: next.workflow,
    );

    next = next.copyWith(
      estimatedStsReminderLeadMinutes: leadMinutes,
      estimatedStsNotificationId: notificationId,
      estimatedStsNotificationStatus: 'scheduled',
      estimatedStsNotificationScheduledAt: scheduledAt,
      estimatedStsCancellationReason: '',
    );
    await _upsertRegistry(next, notificationId: notificationId);
    return StsReminderSyncResult(entry: next);
  }

  Future<OperationsLogEntry> applyLateDecision({
    required OperationsLogEntry entry,
    required bool notifyNow,
    required int leadMinutes,
  }) async {
    final notificationId = entry.estimatedStsNotificationId ??
        _notificationService.notificationIdForSweep(
          entry.sweepId.trim().isEmpty ? entry.entryId : entry.sweepId,
        );

    if (!notifyNow) {
      final next = entry.copyWith(
        estimatedStsReminderChoice: StsReminderChoice.none,
        estimatedStsReminderLeadMinutes: null,
        estimatedStsNotificationId: notificationId,
        estimatedStsNotificationStatus: 'noReminder',
        estimatedStsNotificationScheduledAt: null,
        estimatedStsCancellationReason: 'reminderTimePassed',
      );
      await _upsertRegistry(next, notificationId: notificationId);
      return next;
    }

    await _notificationService.showEstimatedStsReminderNow(
      notificationId: notificationId,
      wellName: entry.wellName,
      leadMinutes: leadMinutes,
    );
    final now = DateTime.now();
    final next = entry.copyWith(
      estimatedStsReminderLeadMinutes: leadMinutes,
      estimatedStsNotificationId: notificationId,
      estimatedStsNotificationStatus: 'delivered',
      estimatedStsNotificationScheduledAt: now,
      estimatedStsCancellationReason: 'notifyNow',
    );
    await _upsertRegistry(next, notificationId: notificationId);
    return next;
  }

  Future<void> cancelForEntry(
    OperationsLogEntry entry, {
    required String reason,
  }) async {
    final id = entry.estimatedStsNotificationId;
    if (id != null) {
      await _notificationService.cancelEstimatedStsReminder(id);
    }
    await _removeRegistry(entry.sweepId);
  }

  Future<void> cancelBySweepId(String sweepId) async {
    final records = await _loadRegistry();
    final target = records[sweepId.trim()];
    if (target == null) return;
    final id = (target['notificationId'] as num?)?.toInt();
    if (id != null) {
      await _notificationService.cancelEstimatedStsReminder(id);
    }
    records.remove(sweepId.trim());
    await _saveRegistry(records);
  }

  Future<void> cancelAllScheduledFromRegistry() async {
    final records = await _loadRegistry();
    final ids = <int>[];
    for (final value in records.values) {
      final id = (value['notificationId'] as num?)?.toInt();
      if (id != null) ids.add(id);
    }
    await _notificationService.cancelEstimatedStsReminders(ids);
  }

  Future<void> updateUseDefaultScheduledReminders({
    required int newDefaultLeadMinutes,
  }) async {
    final records = await _loadRegistry();
    final now = DateTime.now();
    for (final entry in records.values) {
      final choice = (entry['reminderChoice'] as String? ?? '').trim();
      if (choice != StsReminderChoice.useDefault) {
        continue;
      }
      final notificationId = (entry['notificationId'] as num?)?.toInt();
      final estimated =
          DateTime.tryParse(entry['estimatedSts'] as String? ?? '');
      if (notificationId == null ||
          estimated == null ||
          !estimated.isAfter(now)) {
        continue;
      }
      final scheduledAt = estimated.subtract(
        Duration(minutes: newDefaultLeadMinutes),
      );
      if (!scheduledAt.isAfter(now)) {
        await _notificationService.cancelEstimatedStsReminder(notificationId);
        entry['status'] = 'reminderTimePassed';
        entry['scheduledAt'] = null;
        entry['resolvedLeadMinutes'] = newDefaultLeadMinutes;
        continue;
      }

      await _notificationService.scheduleEstimatedStsReminder(
        notificationId: notificationId,
        scheduledAt: scheduledAt,
        wellName: (entry['wellName'] as String? ?? '').trim(),
        leadMinutes: newDefaultLeadMinutes,
        sweepId: (entry['sweepId'] as String? ?? '').trim(),
        entryId: (entry['entryId'] as String? ?? '').trim(),
        persistentJobId: (entry['persistentJobId'] as String? ?? '').trim(),
        workflow: (entry['workflow'] as String? ?? '').trim(),
      );
      entry['status'] = 'scheduled';
      entry['scheduledAt'] = scheduledAt.toIso8601String();
      entry['resolvedLeadMinutes'] = newDefaultLeadMinutes;
    }
    await _saveRegistry(records);
  }

  Future<Map<String, Map<String, dynamic>>> _loadRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_registryKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, Map<String, dynamic>>{};
    }
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return decoded.map(
        (key, value) => MapEntry(
          key,
          Map<String, dynamic>.from(value as Map),
        ),
      );
    } catch (_) {
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<void> _saveRegistry(Map<String, Map<String, dynamic>> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registryKey, jsonEncode(value));
  }

  Future<void> _upsertRegistry(
    OperationsLogEntry entry, {
    required int notificationId,
  }) async {
    final sweepId = entry.sweepId.trim();
    if (sweepId.isEmpty) return;
    final records = await _loadRegistry();
    records[sweepId] = <String, dynamic>{
      'sweepId': sweepId,
      'entryId': entry.entryId,
      'persistentJobId': entry.persistentJobId,
      'workflow': entry.workflow,
      'wellName': entry.wellName,
      'estimatedSts': entry.estimatedSts?.toIso8601String(),
      'reminderChoice': entry.estimatedStsReminderChoice,
      'resolvedLeadMinutes': entry.estimatedStsReminderLeadMinutes,
      'notificationId': notificationId,
      'status': entry.estimatedStsNotificationStatus,
      'scheduledAt':
          entry.estimatedStsNotificationScheduledAt?.toIso8601String(),
    };
    await _saveRegistry(records);
  }

  Future<void> _removeRegistry(String sweepId) async {
    final normalized = sweepId.trim();
    if (normalized.isEmpty) return;
    final records = await _loadRegistry();
    records.remove(normalized);
    await _saveRegistry(records);
  }

  int? _explicitMinutes(String choice) {
    if (!choice.startsWith('minutes:')) return null;
    final raw = choice.substring('minutes:'.length).trim();
    return int.tryParse(raw);
  }
}
