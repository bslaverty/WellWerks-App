import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_settings_service.dart';
import 'rate_timer_service.dart';
import '../utils/quick_round_reminder_utils.dart';

const String rateTimerActionOpen = 'rate_timer_action_open';
const String rateTimerActionStop = 'rate_timer_action_stop';
const String rateTimerActionRestart = 'rate_timer_action_restart';

const String _rateTimerCategoryId = 'rate_timer_actions';
const String _quickRoundChannelId = 'wellwerks_quick_round_hourly_v1';
const String _quickRoundChannelName = 'Quick Round Reminder';
const String _quickRoundChannelDescription =
    'Hourly reminder to collect Quick Round numbers.';

@pragma('vm:entry-point')
void rateTimerNotificationTapBackground(NotificationResponse response) async {
  await RateTimerNotificationService.instance
      .handleNotificationResponse(response);
}

class RateTimerNotificationService {
  RateTimerNotificationService._();

  static final RateTimerNotificationService instance =
      RateTimerNotificationService._();

  static const _permissionPromptedKey =
      'wellwerks_rate_timer_notif_prompted_v1';
  static const quickRoundReminderEnabledKey =
      'wellwerks_quick_round_reminder_enabled_v1';
  static const quickRoundReminderMinuteKey =
      'wellwerks_quick_round_reminder_minute_v1';
  static const quickRoundReminderBaseId = 420000;
  static const quickRoundReminderCount = 24;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final RateTimerService _timerService = RateTimerService();

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    final iosSettings = DarwinInitializationSettings(
      notificationCategories: <DarwinNotificationCategory>[
        actionCategory,
      ],
    );
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(
      iOS: iosSettings,
      android: androidSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          rateTimerNotificationTapBackground,
    );

    _initialized = true;
  }

  Future<bool> ensurePermissionIfNeeded() async {
    await ensureInitialized();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios == null) return true;

    final prefs = await SharedPreferences.getInstance();
    final prompted = prefs.getBool(_permissionPromptedKey) ?? false;
    if (!prompted) {
      await prefs.setBool(_permissionPromptedKey, true);
      final granted = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return granted;
    }
    return true;
  }

  Future<bool> requestNotificationPermission() async {
    await ensureInitialized();

    var granted = true;

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      granted = (await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false);
    }

    final dynamic android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final androidGranted =
          await android.requestNotificationsPermission() ?? true;
      granted = granted && androidGranted;
    }

    return granted;
  }

  Future<void> scheduleQuickRoundReminder({required int minute}) async {
    await ensureInitialized();
    await cancelQuickRoundReminder();

    final normalizedMinute = normalizeQuickRoundReminderMinute(minute);
    final now = tz.TZDateTime.now(tz.local);

    for (var hour = 0; hour < quickRoundReminderCount; hour++) {
      var first = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        normalizedMinute,
      );
      if (!first.isAfter(now)) {
        first = first.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        quickRoundReminderBaseId + hour,
        'WellWerks Quick Round',
        'Time to collect your hourly numbers.',
        first,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _quickRoundChannelId,
            _quickRoundChannelName,
            channelDescription: _quickRoundChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'quick_round_reminder',
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelQuickRoundReminder() async {
    await ensureInitialized();
    for (var hour = 0; hour < quickRoundReminderCount; hour++) {
      await _plugin.cancel(quickRoundReminderBaseId + hour);
    }
  }

  Future<void> syncQuickRoundReminderFromPrefs() async {
    await ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(quickRoundReminderEnabledKey) ?? false;
    final minute = normalizeQuickRoundReminderMinute(
      prefs.getInt(quickRoundReminderMinuteKey) ?? 0,
    );

    if (!enabled) {
      await cancelQuickRoundReminder();
      return;
    }

    await scheduleQuickRoundReminder(minute: minute);
  }

  Future<void> scheduleNotifications({
    required RateTimerState timer,
    required AppSettingsData settings,
  }) async {
    await ensureInitialized();
    await cancelNotifications(timer);

    if (!settings.rateTimerNotificationsEnabled) return;

    final payload = jsonEncode({
      'calculatorId': timer.calculatorId,
      'calculatorTitle': timer.calculatorTitle,
      'wellOrJob': timer.wellOrJob,
      'durationSeconds': timer.durationSeconds,
      'instanceId': timer.instanceId,
    });

    final soundEnabled = settings.rateTimerSoundEnabled;

    if (settings.rateTimerWarningEnabled && timer.durationSeconds > 30) {
      final warningTime =
          tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, timer.endsAtMs)
              .subtract(const Duration(seconds: 30));
      await _plugin.zonedSchedule(
        timer.warningNotificationId,
        'Rate Timer',
        timer.wellOrJob.trim().isNotEmpty
            ? '${timer.wellOrJob.trim()} rate timer ends in 30 seconds.'
            : 'Rate timer ends in 30 seconds.',
        warningTime,
        NotificationDetails(
          iOS: DarwinNotificationDetails(
            categoryIdentifier: _rateTimerCategoryId,
            presentAlert: true,
            presentBanner: true,
            presentBadge: false,
            presentSound: soundEnabled,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: payload,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }

    if (settings.rateTimerCompleteEnabled) {
      final completeTime =
          tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, timer.endsAtMs);
      await _plugin.zonedSchedule(
        timer.completeNotificationId,
        'Rate Timer Complete',
        timer.wellOrJob.trim().isNotEmpty
            ? '${timer.wellOrJob.trim()} rate timer is complete. Record your rate.'
            : 'Rate timer is complete. Record your rate.',
        completeTime,
        NotificationDetails(
          iOS: DarwinNotificationDetails(
            categoryIdentifier: _rateTimerCategoryId,
            presentAlert: true,
            presentBanner: true,
            presentBadge: true,
            presentSound: soundEnabled,
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
        payload: payload,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelNotifications(RateTimerState timer) async {
    await ensureInitialized();
    await _plugin.cancel(timer.warningNotificationId);
    await _plugin.cancel(timer.completeNotificationId);
  }

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    try {
      final payload = jsonDecode(response.payload ?? '{}');
      final map = Map<String, dynamic>.from(payload as Map);
      final action = response.actionId;

      if (action == rateTimerActionStop) {
        await _timerService.setPendingAction(
          RateTimerPendingAction(
            type: RateTimerPendingActionType.stopTimer,
            payload: map,
          ),
        );
        return;
      }

      if (action == rateTimerActionRestart) {
        await _timerService.setPendingAction(
          RateTimerPendingAction(
            type: RateTimerPendingActionType.restartTimer,
            payload: map,
          ),
        );
        return;
      }

      await _timerService.setPendingAction(
        RateTimerPendingAction(
          type: RateTimerPendingActionType.openCalculator,
          payload: map,
        ),
      );
    } catch (err) {
      debugPrint('Rate timer notification response failed: $err');
    }
  }

  DarwinNotificationCategory get actionCategory {
    return DarwinNotificationCategory(
      _rateTimerCategoryId,
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain(
            rateTimerActionOpen, 'Open Rate Calculator'),
        DarwinNotificationAction.plain(rateTimerActionStop, 'Stop Timer'),
        DarwinNotificationAction.plain(rateTimerActionRestart, 'Restart Timer'),
      ],
      options: <DarwinNotificationCategoryOption>{
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    );
  }
}
