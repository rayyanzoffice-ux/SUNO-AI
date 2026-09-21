import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';
import 'backend/alerts/fcm_alert_service.dart';
import 'backend/persistence/app_storage.dart';
import 'backend/persistence/hive_incident_repository.dart';
import 'backend/persistence/hive_trusted_contact_repository.dart';
import 'core/navigation/navigator_key.dart';
import 'core/routes/app_routes.dart';
import 'models/detection_result.dart';
import 'models/incident.dart';
import 'models/received_alert.dart';
import 'services/detection_notification_service.dart';
import 'services/monitoring_service.dart';
import 'services/notification_inbox.dart';
import 'services/suno_runtime_service.dart';

const _inboxPortName = 'suno_notification_inbox';
final _inbox = NotificationInbox();
final _pendingNavigation = <Map<String, String>>[];
Future<void> _draining = Future.value();
ReceivePort? _inboxPort;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  if (message.data['type'] == 'test') return;
  await _inbox.add(Map<String, String>.from(message.data));
  IsolateNameServer.lookupPortByName(_inboxPortName)?.send(null);
}

Map<String, String>? _decodePayload(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return Uri.splitQueryString(value);
  } on FormatException {
    return null;
  }
}

void _onLocalNotificationTap(NotificationResponse response) {
  final data = _decodePayload(response.payload);
  if (data != null) unawaited(_openPayload(data));
}

Future<void> _acceptPayload(Map<String, String> data) async {
  final runtime = SunoRuntimeService.instance;
  if (data['type'] == 'test') return;
  if (data['type'] == 'response') {
    await runtime.applyContactResponse(
      incidentId: data['incidentId'] ?? '',
      responderName: data['responderName'] ?? 'Your contact',
      status: data['status'] ?? '',
      message: data['message'] ?? '',
    );
  } else if (data['type'] != 'safety_check' &&
      data['type'] != 'emergency_alert') {
    await runtime.acceptReceivedAlert(ReceivedAlert.fromData(data));
  }
}

Future<void> _drainInbox() {
  _draining = _draining.then((_) => _inbox.drain(_acceptPayload)).catchError((
    Object _,
  ) {
    SunoRuntimeService.instance.reportError(
      'Some received alerts could not be restored. Reopen SUNO to retry.',
    );
  });
  return _draining;
}

Future<void> _openPayload(Map<String, String> data) async {
  try {
    await _drainInbox();
    await _acceptPayload(data);
    if (data.containsKey('incidentId') && data['type'] != 'test') {
      if (!_pendingNavigation.any(
        (pending) => pending['incidentId'] == data['incidentId'],
      )) {
        _pendingNavigation.add(data);
      }
      _flushNavigation();
    }
  } catch (_) {
    SunoRuntimeService.instance.reportError(
      'Could not open this alert. Please reopen SUNO.',
    );
  }
}

void _flushNavigation() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = navigatorKey.currentState;
    if (navigator == null || _pendingNavigation.isEmpty) return;
    final data = _pendingNavigation.removeAt(0);
    final incident = SunoRuntimeService.instance.incidentById(
      data['incidentId'] ?? '',
    );
    if (incident == null) {
      ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
        const SnackBar(content: Text('This incident is no longer available.')),
      );
    } else if (incident.isReceived) {
      final detection = incident.detectionResult;
      navigator.pushNamed(
        AppRoutes.alertReceived,
        arguments: <String, String>{
          'incidentId': incident.id,
          'senderToken': incident.senderToken ?? '',
          'eventType': detection.eventType,
          'riskScore': '${detection.riskScore}',
          'riskLevel': detection.riskLevel.wireValue,
          'detectedAt': detection.detectedAt.toIso8601String(),
          'isSimulated': '${detection.isSimulated}',
          if (detection.latitude != null) 'latitude': '${detection.latitude}',
          if (detection.longitude != null)
            'longitude': '${detection.longitude}',
          if (detection.locationText != null)
            'locationText': detection.locationText!,
        },
      );
    } else {
      navigator.pushNamed(
        incident.status == IncidentStatus.safetyCheck
            ? AppRoutes.safetyCheck
            : AppRoutes.emergencyAlert,
        arguments: incident.id,
      );
    }
    if (_pendingNavigation.isNotEmpty) _flushNavigation();
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

Future<void> _handleForegroundMessage(RemoteMessage message) async {
  final data = Map<String, String>.from(message.data);
  if (!data.containsKey('incidentId') || data['type'] == 'test') return;
  try {
    await _inbox.add(data);
    await _drainInbox();
    final response = data['type'] == 'response';
    await sunoNotifications.show(
      data['incidentId'].hashCode,
      message.notification?.title ??
          (response ? 'SUNO contact response' : 'SUNO emergency alert'),
      message.notification?.body ??
          (response ? data['message'] : data['eventType']),
      NotificationDetails(
        android: AndroidNotificationDetails(
          emergencyChannelId,
          'SUNO Emergency Alerts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          vibrationPattern: notificationVibration,
        ),
      ),
      payload: Uri(queryParameters: data).query,
    );
  } catch (_) {
    SunoRuntimeService.instance.reportError(
      'Could not process an incoming notification. Please reopen SUNO.',
    );
  }
}

class _AppLifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainInbox().then((_) => _flushNavigation()));
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStorage();
  FcmAlertService? alertService;
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    alertService = FcmAlertService(messaging: FirebaseMessaging.instance);
  } catch (_) {
    /* Local safety history remains available without Firebase. */
  }

  var notificationsReady = false;
  try {
    await sunoNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(
          '@android:drawable/ic_dialog_alert',
        ),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );
    await initDetectionNotificationChannel();
    notificationsReady = true;
  } catch (_) {}
  final runtime = SunoRuntimeService(
    incidentRepository: const HiveIncidentRepository(),
    trustedContactRepository: const HiveTrustedContactRepository(),
    alertService: alertService,
  );
  SunoRuntimeService.instance = runtime;
  await runtime.restoreLatestIncident();
  if (!firebaseReady) {
    runtime.reportError(
      'Push alerts are unavailable. Check Firebase configuration and restart SUNO.',
    );
  }
  if (!notificationsReady) {
    runtime.reportError(
      'Notifications unavailable. Keep SUNO open and check Android notification settings.',
    );
  }
  MonitoringService.instance;

  _inboxPort = ReceivePort()..listen((_) => _drainInbox());
  IsolateNameServer.removePortNameMapping(_inboxPortName);
  IsolateNameServer.registerPortWithName(_inboxPort!.sendPort, _inboxPortName);
  WidgetsBinding.instance.addObserver(_AppLifecycle());
  await _drainInbox();
  if (notificationsReady) {
    try {
      final launch = await sunoNotifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final payload = _decodePayload(launch?.notificationResponse?.payload);
        if (payload != null) await _openPayload(payload);
      }
    } catch (_) {
      runtime.reportError(
        'Could not restore the tapped notification. Open incident history.',
      );
    }
  }
  if (firebaseReady) {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openPayload(Map<String, String>.from(message.data)),
    );
    try {
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 8));
      if (initial != null) {
        await _openPayload(Map<String, String>.from(initial.data));
      }
    } catch (_) {
      runtime.reportError(
        'Could not restore the launch alert. Open incident history.',
      );
    }
  }
  runApp(const SunoApp());
  _flushNavigation();
  if (alertService != null) {
    unawaited(
      alertService.registerDevice().catchError((Object _) {
        runtime.reportError(
          'Push token unavailable. Check connectivity and notification permission, then retry from Trusted Contacts.',
        );
        return null;
      }),
    );
  }
}
