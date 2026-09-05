import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';
import 'backend/alerts/fcm_alert_service.dart';
import 'backend/persistence/app_storage.dart';
import 'backend/persistence/hive_incident_repository.dart';
import 'backend/persistence/hive_trusted_contact_repository.dart';
import 'core/config/app_config.dart';
import 'core/routes/app_routes.dart';
import 'services/suno_runtime_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final _localNotifications = FlutterLocalNotificationsPlugin();
bool _localNotificationsInitialized = false;

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background/terminated messages are handled by the system notification
  // tray; we do not need to show a local notification here.
}

@pragma('vm:entry-point')
void _onLocalNotificationTap(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  _navigateToAlertReceived(_parsePayload(payload));
}

Map<String, String> _parsePayload(String payload) {
  final map = <String, String>{};
  for (final entry in payload.split('&')) {
    final parts = entry.split('=');
    if (parts.length == 2) {
      map[parts[0]] = Uri.decodeComponent(parts[1]);
    }
  }
  return map;
}

String _encodePayload(Map<String, String> data) {
  return data.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

void _navigateToAlertReceived(Map<String, String> data) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  Navigator.pushNamed(context, AppRoutes.alertReceived, arguments: data);
}

Future<void> _initLocalNotifications() async {
  if (_localNotificationsInitialized) return;
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: _onLocalNotificationTap,
    onDidReceiveBackgroundNotificationResponse: _onLocalNotificationTap,
  );

  const channel = AndroidNotificationChannel(
    'suno_alerts',
    'SUNO Emergency Alerts',
    description: 'High-priority alerts from trusted contacts',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('notification'),
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  _localNotificationsInitialized = true;
}

Future<void> _handleRemoteMessage(RemoteMessage message,
    {bool showLocalNotification = false}) async {
  final data = Map<String, String>.from(message.data);
  final type = data['type'];

  if (type == 'response') {
    await SunoRuntimeService.instance.applyContactResponse(
      incidentId: data['incidentId'] ?? '',
      responderName: data['responderName'] ?? 'Your contact',
      status: data['status'] ?? 'contactChecking',
      message: data['message'] ?? '',
    );
    return;
  }

  if (showLocalNotification && data.containsKey('incidentId')) {
    await _localNotifications.show(
      data['incidentId']!.hashCode,
      message.notification?.title ?? 'SUNO emergency alert',
      message.notification?.body ??
          '${data['eventType'] ?? 'Emergency'} · Risk ${data['riskScore'] ?? '?'}%',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'suno_alerts',
          'SUNO Emergency Alerts',
          channelDescription: 'High-priority alerts from trusted contacts',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'SUNO emergency alert',
        ),
      ),
      payload: _encodePayload(data),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initStorage();

  final relayUrl = AppConfig.alertRelayUrl;
  if (relayUrl.trim().isEmpty) {
    // ignore: avoid_print
    print(
      '[SUNO] WARNING: SUNO_ALERT_RELAY_URL is empty. '
      'Push alerts to trusted contacts will be silently disabled.',
    );
  } else {
    // ignore: avoid_print
    print('[SUNO] Alert relay resolved to: $relayUrl');
  }

  FcmAlertService? alertService;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    alertService = FcmAlertService(messaging: FirebaseMessaging.instance);
    await alertService.registerDevice();
  } catch (_) {
    alertService = null;
  }

  await _initLocalNotifications();

  SunoRuntimeService.instance = SunoRuntimeService(
    incidentRepository: const HiveIncidentRepository(),
    trustedContactRepository: const HiveTrustedContactRepository(),
    alertService: alertService,
  );

  FirebaseMessaging.onMessage.listen(
    (message) => _handleRemoteMessage(message, showLocalNotification: true),
  );
  FirebaseMessaging.onMessageOpenedApp.listen(
    (message) => _handleRemoteMessage(message),
  );

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  Map<String, String>? pendingAlertPayload;
  if (initialMessage != null &&
      initialMessage.data.containsKey('incidentId') &&
      initialMessage.data['type'] != 'response') {
    pendingAlertPayload = Map<String, String>.from(initialMessage.data);
  }

  runApp(const SunoApp(navigatorKey: navigatorKey));

  if (pendingAlertPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToAlertReceived(pendingAlertPayload!);
    });
  }
}
