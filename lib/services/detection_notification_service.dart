import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const int _detectionNotificationId = 9001;

final _plugin = FlutterLocalNotificationsPlugin();
bool _channelCreated = false;

Future<void> initDetectionNotificationChannel() async {
  if (_channelCreated) return;
  final android = _plugin.resolvePlatformSpecificImplementation<
    AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      'suno_detection',
      'SUNO Danger Detected',
      description: 'Interrupts when danger is detected while backgrounded',
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: [0, 400, 200, 400, 200, 800],
      playSound: true,
    ),
  );
  _channelCreated = true;
}

Future<void> showFullScreenDetectionNotification({
  required String title,
  required String body,
  required bool isCritical,
}) async {
  const androidDetails = AndroidNotificationDetails(
    'suno_detection',
    'SUNO Danger Detected',
    channelDescription: 'Interrupts when danger is detected while backgrounded',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    enableVibration: true,
    vibrationPattern: [0, 400, 200, 400, 200, 800],
    ticker: 'SUNO: Danger detected',
    category: AndroidNotificationCategory.alarm,
  );
  await _plugin.show(
    _detectionNotificationId,
    title,
    body,
    const NotificationDetails(android: androidDetails),
    payload: isCritical ? 'type=emergency_alert' : 'type=safety_check',
  );
}
