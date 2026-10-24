import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/l10n/l10n.dart';

const emergencyChannelId = 'suno_alerts_v2';
const detectionChannelId = 'suno_detection_v2';
// v4: sound and vibration both come from AlarmPlayer, so they do not depend on
// notification permission or the activity being visible. The channel is silent
// and does not vibrate: Android replaces any ongoing vibration with a
// notification's vibration, which would cut the countdown waveform to a single
// pulse. A new id is required because Android freezes channel settings.
const localAlarmChannelId = 'suno_local_alarm_v4';
const _detectionNotificationId = 9001;
final notificationVibration = Int64List.fromList([0, 400, 200, 400, 200, 800]);
final sunoNotifications = FlutterLocalNotificationsPlugin();

Future<void> initDetectionNotificationChannel() async {
  // Channel text is written once per launch, so a language change reaches
  // Android's notification settings only after SUNO is restarted.
  final android = sunoNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  for (final channel in [
    AndroidNotificationChannel(
      emergencyChannelId,
      tr.chanEmergencyName,
      description: tr.chanEmergencyDesc,
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: notificationVibration,
      playSound: true,
    ),
    AndroidNotificationChannel(
      detectionChannelId,
      tr.chanDangerName,
      description: tr.chanDangerDesc,
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: notificationVibration,
      playSound: true,
    ),
    // Silent and still on purpose: tune and vibration come from AlarmPlayer.
    // A notification vibration would cancel that ongoing waveform.
    AndroidNotificationChannel(
      localAlarmChannelId,
      tr.chanLocalAlarmName,
      description: tr.chanLocalAlarmDesc,
      importance: Importance.max,
      enableVibration: false,
      playSound: false,
    ),
  ]) {
    await android?.createNotificationChannel(channel);
  }
}

Future<void> cancelDetectionNotification() =>
    sunoNotifications.cancel(_detectionNotificationId);

Future<void> showFullScreenDetectionNotification({
  required String incidentId,
  required String title,
  required String body,
  required bool isCritical,
  // The safety countdown already rings and vibrates through AlarmPlayer; a
  // vibration here would replace that waveform with one pulse.
  bool safetyCheck = false,
}) async {
  await sunoNotifications.show(
    _detectionNotificationId,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        safetyCheck ? localAlarmChannelId : detectionChannelId,
        safetyCheck ? tr.chanLocalAlarmName : tr.chanDangerName,
        channelDescription: safetyCheck ? tr.chanLocalAlarmDesc : null,
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        enableVibration: !safetyCheck,
        vibrationPattern: safetyCheck ? null : notificationVibration,
        playSound: !safetyCheck,
        category: AndroidNotificationCategory.alarm,
      ),
    ),
    payload: Uri(
      queryParameters: {
        'type': isCritical ? 'emergency_alert' : 'safety_check',
        'incidentId': incidentId,
      },
    ).query,
  );
}
