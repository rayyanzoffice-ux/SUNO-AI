import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const emergencyChannelId = 'suno_alerts_v2';
const detectionChannelId = 'suno_detection_v2';
const _detectionNotificationId = 9001;
final notificationVibration = Int64List.fromList([0, 400, 200, 400, 200, 800]);
final sunoNotifications = FlutterLocalNotificationsPlugin();

Future<void> initDetectionNotificationChannel() async {
  final android = sunoNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  for (final channel in [
    AndroidNotificationChannel(
      emergencyChannelId,
      'SUNO Emergency Alerts',
      description: 'Emergency alerts and responses from trusted contacts',
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: notificationVibration,
      playSound: true,
    ),
    AndroidNotificationChannel(
      detectionChannelId,
      'SUNO Danger Detected',
      description: 'Safety checks and danger detected on this device',
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: notificationVibration,
      playSound: true,
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
        'SUNO Danger Detected',
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
