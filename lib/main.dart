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
import 'backend/persistence/hive_profile_repository.dart';
import 'backend/persistence/hive_trusted_contact_repository.dart';
import 'core/navigation/alert_navigation.dart';
import 'core/navigation/navigator_key.dart';
import 'core/routes/app_routes.dart';
import 'models/incident.dart';
import 'models/received_alert.dart';
import 'screens/alert_received/alert_received_screen.dart';
import 'services/alert_surfacing.dart';
import 'services/detection_notification_service.dart';
import 'services/monitoring_service.dart';
import 'services/notification_inbox.dart';
import 'services/suno_runtime_service.dart';

const _inboxPortName = 'suno_notification_inbox';
final _inbox = NotificationInbox();
final _pendingNavigation = <Map<String, String>>[];
final _surfacedAlertIds = <String>{};
int _navigationRetries = 0;
Future<void> _draining = Future.value();
ReceivePort? _inboxPort;

/// Tagged log line so notification routing can be followed in `adb logcat`.
void _log(String message) => debugPrint('[SUNO-NAV] $message');

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  final kind = message.data['type'];
  final incidentId = message.data['incidentId'];
  _log('bg handler type=$kind incident=$incidentId');
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
  if (data != null) unawaited(_openPayload(data, source: 'local_tap'));
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
    Object error,
    StackTrace stack,
  ) {
    _log('drain inbox FAILED: $error\n$stack');
    SunoRuntimeService.instance.reportError(
      'Some received alerts could not be restored. Reopen SUNO to retry.',
    );
  });
  return _draining;
}

Future<void> _openPayload(
  Map<String, String> data, {
  String source = 'unknown',
}) async {
  final kind = data['type'];
  final incidentId = data['incidentId'];
  _log('open payload source=$source type=$kind incident=$incidentId');
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
  } catch (error, stack) {
    _log('open payload FAILED source=$source: $error\n$stack');
    SunoRuntimeService.instance.reportError(
      'Could not open this alert. Please reopen SUNO.',
    );
  }
}

void _flushNavigation() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_pendingNavigation.isEmpty) {
      _navigationRetries = 0;
      return;
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _retryNavigationLater();
      return;
    }
    _navigationRetries = 0;
    _navigateToIncident(navigator, _pendingNavigation.removeAt(0));
    if (_pendingNavigation.isNotEmpty) _flushNavigation();
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// The navigator can be null for a moment while the Activity re-attaches to
/// the persistent engine. Try again shortly instead of dropping the tap.
void _retryNavigationLater() {
  if (_navigationRetries >= 40) {
    _log('gave up waiting for navigator, pending=${_pendingNavigation.length}');
    return;
  }
  _navigationRetries++;
  Future<void>.delayed(const Duration(milliseconds: 150), _flushNavigation);
}

void _navigateToIncident(NavigatorState navigator, Map<String, String> data) {
  final id = data['incidentId'] ?? '';
  final incident = SunoRuntimeService.instance.incidentById(id);
  _log(
    'navigate incident=$id found=${incident != null} received=${incident?.isReceived}',
  );
  if (incident == null) {
    ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
      const SnackBar(content: Text('This incident is no longer available.')),
    );
    return;
  }
  if (incident.isReceived) {
    if (AlertReceivedScreen.visibleIncidentId.value == incident.id) {
      _log('alert screen already visible for $id, not pushing again');
      return;
    }
    _surfacedAlertIds.add(incident.id);
    navigator.pushNamed(
      AppRoutes.alertReceived,
      arguments: alertReceivedArguments(incident),
    );
    return;
  }
  navigator.pushNamed(
    incident.status == IncidentStatus.safetyCheck
        ? AppRoutes.safetyCheck
        : AppRoutes.emergencyAlert,
    arguments: incident.id,
  );
}

/// Opens the newest recent, unanswered, critical alert from a trusted contact.
///
/// Safety net for notification taps that Firebase never reports: the alert
/// data is already stored, so we can show it whenever the app starts or
/// resumes. Never interrupts the user's OWN safety check or alert dispatch.
Future<void> _surfaceUnseenAlert() async {
  try {
    final runtime = SunoRuntimeService.instance;
    if (runtime.hasPendingSafetyCheck || runtime.hasPendingDispatch) return;
    final candidate = pickUnseenReceivedAlert(
      runtime.knownIncidents,
      now: DateTime.now(),
      alreadySurfaced: _surfacedAlertIds,
    );
    if (candidate == null) return;
    if (_pendingNavigation.any((p) => p['incidentId'] == candidate.id)) return;
    _log('surfacing unseen alert ${candidate.id}');
    _pendingNavigation.add(<String, String>{'incidentId': candidate.id});
    _flushNavigation();
  } catch (error, stack) {
    _log('surface unseen alert FAILED: $error\n$stack');
  }
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
  } catch (error, stack) {
    _log('foreground message FAILED: $error\n$stack');
    SunoRuntimeService.instance.reportError(
      'Could not process an incoming notification. Please reopen SUNO.',
    );
  }
}

Future<void> _onResumed() async {
  await _drainInbox();
  _flushNavigation();
  await _surfaceUnseenAlert();
}

class _AppLifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _log('lifecycle resumed');
      unawaited(_onResumed());
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
  } catch (error, stack) {
    // Local safety history remains available without Firebase.
    _log('firebase init FAILED: $error\n$stack');
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
  } catch (error, stack) {
    _log('notification init FAILED: $error\n$stack');
  }
  final runtime = SunoRuntimeService(
    incidentRepository: const HiveIncidentRepository(),
    trustedContactRepository: const HiveTrustedContactRepository(),
    profileRepository: const HiveProfileRepository(),
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
        if (payload != null) {
          await _openPayload(payload, source: 'local_launch');
        }
      }
    } catch (error, stack) {
      _log('launch details FAILED: $error\n$stack');
      runtime.reportError(
        'Could not restore the tapped notification. Open incident history.',
      );
    }
  }
  if (firebaseReady) {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(
        _openPayload(
          Map<String, String>.from(message.data),
          source: 'fcm_opened_app',
        ),
      );
    });
    try {
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 8));
      final initialId = initial == null ? null : initial.data['incidentId'];
      _log('getInitialMessage -> $initialId');
      if (initial != null) {
        await _openPayload(
          Map<String, String>.from(initial.data),
          source: 'fcm_initial',
        );
      }
    } catch (error, stack) {
      _log('getInitialMessage FAILED: $error\n$stack');
      runtime.reportError(
        'Could not restore the launch alert. Open incident history.',
      );
    }
  }
  runApp(const SunoApp());
  _flushNavigation();
  unawaited(_surfaceUnseenAlert());
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
