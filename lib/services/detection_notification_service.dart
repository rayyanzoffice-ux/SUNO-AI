import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/l10n/l10n.dart';

const emergencyChannelId = 'suno_alerts_v2';
const detectionChannelId = 'suno_detection_v2';
// v3: the tune is played by AlarmPlayer on the alarm audio stream, which does
// not depend on notification permission or the activity being visible. The
// channel is silent so the two can never overlap. A new id is required because
// Android freezes a channel's sound after creation.
const localAlarmChannelId = 'suno_local_alarm_v3';
const _detectionNotificationId = 9001;
final notificationVibration = Int64List.fromList([0, 400, 200, 400, 200, 800]);
final alarmVibration = Int64List.fromList([0, 600, 300, 600]);
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
    // Silent on purpose: the tune comes from AlarmPlayer, so muting the
    // notification stream cannot silence the alarm. Vibration stays here.
    AndroidNotificationChannel(
      localAlarmChannelId,
      tr.chanLocalAlarmName,
      description: tr.chanLocalAlarmDesc,
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: alarmVibration,
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
}) async {
  await sunoNotifications.show(
    _detectionNotificationId,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        detectionChannelId,
        tr.chanDangerName,
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        enableVibration: true,
        vibrationPattern: notificationVibration,
        playSound: true,
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
