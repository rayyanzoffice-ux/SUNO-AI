import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'backend/alerts/fcm_alert_service.dart';
import 'backend/persistence/app_storage.dart';
import 'backend/persistence/hive_incident_repository.dart';
import 'backend/persistence/hive_trusted_contact_repository.dart';
import 'core/navigation/navigator_key.dart';
import 'core/routes/app_routes.dart';
import 'models/received_alert.dart';
import 'services/suno_runtime_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

final Set<String> _handledMessageIds = <String>{};

void _storeReceivedMessage(RemoteMessage message) {
  SunoRuntimeService.instance.acceptReceivedAlert(
    ReceivedAlert.fromData(message.data),
  );
}

void _handleNotificationTap(RemoteMessage message) {
  final messageId = message.messageId;
  if (messageId != null && !_handledMessageIds.add(messageId)) return;
  _storeReceivedMessage(message);
  navigatorKey.currentState?.pushNamed(AppRoutes.trustedContactView);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initStorage();

  FcmAlertService? alertService;
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    alertService = FcmAlertService(messaging: FirebaseMessaging.instance);
    await alertService.registerDevice();
  } catch (_) {
    alertService = null;
  }

  SunoRuntimeService.instance = SunoRuntimeService(
    incidentRepository: const HiveIncidentRepository(),
    trustedContactRepository: const HiveTrustedContactRepository(),
    alertService: alertService,
  );

  RemoteMessage? initialMessage;
  if (firebaseReady) {
    FirebaseMessaging.onMessage.listen(_storeReceivedMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  }

  runApp(const SunoApp());

  if (initialMessage != null) {
    final message = initialMessage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(message);
    });
  }
}
