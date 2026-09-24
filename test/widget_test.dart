import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/services/foreground_service_bridge.dart';
import 'package:suno_ai/models/received_alert.dart';
import 'package:suno_ai/models/trusted_contact.dart';
import 'package:suno_ai/screens/alert_received/alert_received_screen.dart';
import 'package:suno_ai/widgets/primary_action_button.dart';
import 'package:suno_ai/widgets/silent_sos_sheet.dart';
import 'package:suno_ai/app.dart';
import 'package:suno_ai/backend/backend_exports.dart';
import 'package:suno_ai/core/routes/app_routes.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/screens/contacts_setup/contacts_setup_screen.dart';
import 'package:suno_ai/screens/emergency_alert/emergency_alert_screen.dart';
import 'package:suno_ai/screens/history/history_screen.dart';
import 'package:suno_ai/screens/home/home_screen.dart';
import 'package:suno_ai/screens/monitoring/monitoring_screen.dart';
import 'package:suno_ai/screens/safety_check/safety_check_screen.dart';
import 'package:suno_ai/services/suno_runtime_service.dart';
import 'package:suno_ai/services/monitoring_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SunoRuntimeService.instance = SunoRuntimeService(
      locationService: _UnavailableLocation(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.suno_ai/monitoring_service'),
          (call) async {
            if (call.method == 'start') {
              expect(call.arguments['microphoneEnabled'], isFalse);
            }
            return null;
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (_) async => null,
        );
  });
  tearDown(() {
    MonitoringService.resetForTesting();
    SunoRuntimeService.instance.dispose();
  });
  testWidgets('home offers the critical demo entry points', (tester) async {
    await tester.pumpWidget(const SunoApp());
    expect(find.text('SUNO'), findsOneWidget);
    expect(find.text('START MONITORING'), findsOneWidget);
    expect(find.text('Trusted Contacts'), findsOneWidget);
  });

  testWidgets('switching to Demo clears stale Live monitoring errors', (
    tester,
  ) async {
    final monitoring = MonitoringService.instance;
    monitoring.error = 'Old audio failure';
    monitoring.motionWarning = 'Old motion warning';

    await monitoring.selectDemo();

    expect(monitoring.liveMode, isFalse);
    expect(monitoring.error, isNull);
    expect(monitoring.motionWarning, isNull);
  });

  testWidgets('home can launch low demo without creating an incident', (
    tester,
  ) async {
    await tester.pumpWidget(const SunoApp());
    await tester.tap(find.text('START MONITORING'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('LOW'));
    await _tapSimulateDistress(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.textContaining('The microphone is off in Demo mode.'),
      findsOneWidget,
    );
    expect(find.text('Emergency Alert Activated'), findsNothing);
    expect(find.text('Are you safe?'), findsNothing);
    expect(SunoRuntimeService.instance.currentIncident, isNull);
  });

  testWidgets('low detection remains on Monitoring', (tester) async {
    await _pumpScenario(tester, DetectionScenario.low);
    await _tapSimulateDistress(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.textContaining('The microphone is off in Demo mode.'),
      findsOneWidget,
    );
    expect(find.text('Emergency Alert Activated'), findsNothing);
    expect(find.text('Are you safe?'), findsNothing);
  });

  testWidgets('medium detection opens Safety Check and safe cancels incident', (
    tester,
  ) async {
    await _pumpScenario(tester, DetectionScenario.medium);
    await _tapSimulateDistress(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(SunoRuntimeService.instance.currentIncident, isNotNull);
    expect(find.text('Are you safe?'), findsOneWidget);
    await tester.tap(find.text('I AM SAFE'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The microphone is off in Demo mode.'),
      findsOneWidget,
    );
    expect(
      SunoRuntimeService.instance.currentIncident?.status,
      IncidentStatus.cancelled,
    );
  });

  testWidgets(
    'medium detection can escalate immediately when user cannot respond',
    (tester) async {
      await _pumpScenario(tester, DetectionScenario.medium);
      await _tapSimulateDistress(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Are you safe?'), findsOneWidget);
      await tester.tap(find.text("CAN'T RESPOND"));
      await tester.pumpAndSettle();

      expect(find.text('Emergency Alert Activated'), findsOneWidget);
      expect(
        SunoRuntimeService.instance.currentIncident?.status,
        IncidentStatus.alertTriggered,
      );
    },
  );

  testWidgets('medium detection timeout escalates to emergency alert', (
    tester,
  ) async {
    await _pumpScenario(tester, DetectionScenario.medium);
    await _tapSimulateDistress(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Are you safe?'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    expect(find.text('Emergency Alert Activated'), findsOneWidget);
    expect(
      SunoRuntimeService.instance.currentIncident?.status,
      IncidentStatus.alertTriggered,
    );
  });

  testWidgets('critical detection opens Emergency Alert immediately', (
    tester,
  ) async {
    await _pumpScenario(tester, DetectionScenario.critical);
    await _tapSimulateDistress(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Emergency Alert Activated'), findsOneWidget);
    expect(find.text('95% (Critical)'), findsOneWidget);

    await tester.ensureVisible(find.text('View incident history'));
    await tester.tap(find.text('View incident history'));
    await tester.pumpAndSettle();
    expect(find.text('Incident History'), findsOneWidget);
    expect(find.text('Distress Sound + Impact'), findsOneWidget);
  });

  testWidgets('history shows empty state without fabricated incidents', (
    tester,
  ) async {
    final runtime = SunoRuntimeService(
      incidentRepository: InMemoryIncidentRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(runtimeService: runtime)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No incidents yet'), findsOneWidget);
    expect(find.text('61%'), findsNothing);
    expect(find.text('58%'), findsNothing);
  });

  testWidgets('history uses repository data and status filters', (
    tester,
  ) async {
    final repository = InMemoryIncidentRepository();
    final runtime = SunoRuntimeService(incidentRepository: repository);
    final cancelled = _historyIncident(
      id: 'cancelled',
      eventType: 'Cancelled Demo Event',
      riskScore: 50,
      status: IncidentStatus.cancelled,
      createdAt: DateTime(2026, 8, 26, 20),
    );
    final critical = _historyIncident(
      id: 'critical',
      eventType: 'Critical Demo Event',
      riskScore: 95,
      status: IncidentStatus.alertTriggered,
      createdAt: DateTime(2026, 8, 26, 21),
    );
    await repository.save(cancelled);
    await repository.save(critical);

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(runtimeService: runtime)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Critical Demo Event'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('Cancelled Demo Event'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Critical Demo Event')).dy,
      lessThan(tester.getTopLeft(find.text('Cancelled Demo Event')).dy),
    );

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('Critical Demo Event'), findsOneWidget);
    expect(find.text('Cancelled Demo Event'), findsNothing);

    await tester.tap(find.text('Canceled'));
    await tester.pumpAndSettle();
    expect(find.text('Critical Demo Event'), findsNothing);
    expect(find.text('Cancelled Demo Event'), findsOneWidget);
    expect(find.text('61%'), findsNothing);
    expect(find.text('58%'), findsNothing);
  });

  testWidgets('history recovers after load and swipe-delete failures', (
    tester,
  ) async {
    final repository = _FlakyIncidents()..failLoad = true;
    final runtime = SunoRuntimeService(incidentRepository: repository);
    addTearDown(runtime.dispose);
    await repository.save(
      _historyIncident(
        id: 'saved',
        eventType: 'Saved event',
        riskScore: 95,
        status: IncidentStatus.resolved,
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(runtimeService: runtime)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load history. Please retry.'), findsOneWidget);
    repository.failLoad = false;
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    repository.failRemove = true;
    await tester.drag(
      find.byKey(const ValueKey('saved')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved event'), findsOneWidget);
    expect(
      find.text('Could not delete the incident. Please retry.'),
      findsOneWidget,
    );
    repository.failRemove = false;
    await tester.drag(
      find.byKey(const ValueKey('saved')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('No incidents yet'), findsOneWidget);
    expect(await repository.getAll(), isEmpty);
  });

  testWidgets(
    'safety save failure stays actionable and retries the same incident',
    (tester) async {
      SunoRuntimeService.instance.dispose();
      final repository = _FlakyIncidents();
      final runtime = SunoRuntimeService(
        incidentRepository: repository,
        locationService: _UnavailableLocation(),
      );
      SunoRuntimeService.instance = runtime;
      await _pumpScenario(tester, DetectionScenario.medium);
      await _tapSimulateDistress(tester);
      final incident = runtime.currentIncident!;
      expect(find.text('Are you safe?'), findsOneWidget);
      repository.failUpdate = true;
      await tester.tap(find.text('I AM SAFE'));
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pump();
      expect(find.text('RETRY: I AM SAFE'), findsOneWidget);
      expect(find.textContaining('No alert was sent.'), findsOneWidget);
      repository.failUpdate = false;
      await tester.tap(find.text('RETRY: I AM SAFE'));
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The microphone is off in Demo mode.'),
        findsOneWidget,
      );
      expect(runtime.currentIncident?.id, incident.id);
      expect(runtime.currentIncident?.status, IncidentStatus.cancelled);
    },
  );

  testWidgets('contacts recover from load, save, test and delete failures', (
    tester,
  ) async {
    final contacts = _FlakyContacts()..failLoad = true;
    final alerts = _TestAlerts();
    SunoRuntimeService.instance.dispose();
    SunoRuntimeService.instance = SunoRuntimeService(
      trustedContactRepository: contacts,
      alertService: alerts,
    );
    await tester.pumpWidget(const MaterialApp(home: ContactsSetupScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your saved contacts.'), findsOneWidget);
    contacts.failLoad = false;
    await tester.tap(find.text('RETRY CONTACTS'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Test contact');
    await tester.enterText(fields.at(2), 'Friend');
    await tester.enterText(fields.at(3), 'synthetic-recipient-token-12345');
    contacts.failSave = true;
    await tester.ensureVisible(find.text('SAVE CONTACT'));
    await tester.tap(find.text('SAVE CONTACT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your entries are still here'), findsOneWidget);
    expect(
      tester.widget<TextField>(fields.at(0)).controller!.text,
      'Test contact',
    );
    contacts.failSave = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE CONTACT'));
    await tester.pumpAndSettle();
    expect((await contacts.getAll()).single.name, 'Test contact');
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(PopupMenuButton<String>));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    alerts.failTest = true;
    await tester.tap(find.text('Test FCM acceptance'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test failed:'), findsOneWidget);
    expect((await contacts.getAll()).single.verifiedAt, isNull);
    alerts.failTest = false;
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test FCM acceptance'));
    await tester.pumpAndSettle();
    expect((await contacts.getAll()).single.verifiedAt, isNotNull);
    contacts.failRemove = true;
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();
    expect((await contacts.getAll()), hasLength(1));
    expect(find.text('Test contact'), findsOneWidget);
    contacts.failRemove = false;
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();
    expect(await contacts.getAll(), isEmpty);
    expect(find.text('Test contact'), findsNothing);
  });

  testWidgets(
    'received response failure retries and resolved or missing alerts disable actions',
    (tester) async {
      final alerts = _TestAlerts()..failResponse = true;
      SunoRuntimeService.instance.dispose();
      final runtime = SunoRuntimeService(alertService: alerts);
      SunoRuntimeService.instance = runtime;
      final payload = <String, String>{
        'incidentId': 'received-1',
        'eventType': 'Distress Sound',
        'riskLevel': 'critical',
        'riskScore': '95',
        'detectedAt': DateTime.now().toIso8601String(),
        'senderToken': 'synthetic-sender-token-12345',
      };
      final accepted = runtime.acceptReceivedAlert(
        ReceivedAlert.fromData(payload),
      );
      await tester.pump();
      await accepted;
      await tester.pumpWidget(
        MaterialApp(home: AlertReceivedScreen(payload: payload)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('THEY ARE SAFE'));
      await tester.tap(find.text('THEY ARE SAFE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Response failed:'), findsOneWidget);
      expect(
        runtime.incidentById('received-1')!.status,
        isNot(IncidentStatus.resolved),
      );
      alerts.failResponse = false;
      await tester.tap(find.text('THEY ARE SAFE'));
      await tester.pumpAndSettle();
      expect(
        runtime.incidentById('received-1')!.status,
        IncidentStatus.resolved,
      );
      expect(alerts.responseIds, ['received-1', 'received-1']);
      expect(find.text('Incident resolved'), findsOneWidget);
      for (final button in tester.widgetList<PrimaryActionButton>(
        find.byType(PrimaryActionButton),
      )) {
        expect(button.onPressed, isNull);
      }
      final removed = runtime.removeIncident('received-1');
      await tester.pump();
      await removed;
      await tester.pumpAndSettle();
      expect(
        find.text('No response can be sent for this incident.'),
        findsOneWidget,
      );
      for (final button in tester.widgetList<PrimaryActionButton>(
        find.byType(PrimaryActionButton),
      )) {
        expect(button.onPressed, isNull);
      }
    },
  );

  testWidgets(
    'Silent SOS retries failed storage and navigates with the saved ID',
    (tester) async {
      final contacts = _FlakyContacts()..failLoad = true;
      final incidents = _FlakyIncidents()..failSave = true;
      SunoRuntimeService.instance.dispose();
      final runtime = SunoRuntimeService(
        trustedContactRepository: contacts,
        incidentRepository: incidents,
        locationService: _UnavailableLocation(),
      );
      SunoRuntimeService.instance = runtime;
      String? openedId;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSilentSosSheet(context),
                child: const Text('Open SOS'),
              ),
            ),
          ),
          routes: {
            AppRoutes.emergencyAlert: (context) {
              openedId = ModalRoute.of(context)!.settings.arguments as String;
              return const Scaffold(body: Text('SOS incident opened'));
            },
          },
        ),
      );
      await tester.tap(find.text('Open SOS'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load contacts.'), findsOneWidget);
      contacts.failLoad = false;
      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ALERT ALL CONTACTS'));
      await tester.tap(find.text('ALERT ALL CONTACTS'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save the SOS.'), findsOneWidget);
      expect(runtime.currentIncident, isNull);
      incidents.failSave = false;
      await tester.tap(find.text('ALERT ALL CONTACTS'));
      await tester.pumpAndSettle();
      expect(find.text('SOS incident opened'), findsOneWidget);
      expect(openedId, runtime.currentIncident!.id);
      expect(
        runtime.currentIncident!.detectionResult.eventType,
        'Manual Silent Alert',
      );
      expect(runtime.currentIncident!.dispatchResult!.success, isFalse);
      expect(await incidents.getAll(), hasLength(1));
    },
  );

  testWidgets('native startup timeout cancels the pending service', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final start = Completer<void>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.suno_ai/monitoring_service'),
          (call) async {
            calls.add(call.method);
            if (call.method == 'start') await start.future;
            return null;
          },
        );
    final failed = expectLater(
      ForegroundServiceBridge.start(microphoneEnabled: false),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 16));
    await failed;
    expect(calls, ['start', 'stop']);
    start.complete();
    await tester.pump();
  });

  testWidgets('native Stop waits for the destruction acknowledgment', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final acknowledgment = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.suno_ai/monitoring_service'),
          (_) => acknowledgment.future,
        );
    var stopped = false;
    final stopping = ForegroundServiceBridge.stop().then((_) => stopped = true);
    await tester.pump();
    expect(stopped, isFalse);
    acknowledgment.complete();
    await tester.pump();
    await stopping;
    expect(stopped, isTrue);
  });

  testWidgets('required screens render at Android phone sizes', (tester) async {
    await tester.runAsync(
      () => SunoRuntimeService.instance.recordDetection(
        DetectionResult(
          eventType: 'Possible Distress Sound',
          confidence: .9,
          impactDetected: false,
          stillnessDetected: false,
          riskScore: 50,
          riskLevel: RiskLevel.medium,
          detectedAt: DateTime.now(),
        ),
      ),
    );
    final monitoringRuntime = SunoRuntimeService(
      locationService: _UnavailableLocation(),
    );
    addTearDown(monitoringRuntime.dispose);
    final sizes = [
      const Size(360, 800),
      const Size(390, 844),
      const Size(412, 915),
    ];
    final screens = <Widget>[
      const HomeScreen(),
      MonitoringScreen(runtime: monitoringRuntime),
      const SafetyCheckScreen(),
      const EmergencyAlertScreen(),
      const HistoryScreen(),
      const ContactsSetupScreen(),
    ];

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final size in sizes) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;

      for (final screen in screens) {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.runtimeType} at ${size.width}x${size.height}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  test('backend mock inputs still produce the API contract values', () async {
    final result = await SunoRuntimeService.instance.runDetection(
      DetectionScenario.critical,
    );
    final json = result.toJson(status: IncidentStatus.alertTriggered.wireValue);

    expect(json['riskLevel'], 'critical');
    expect(json['locationText'], isNull);
    expect(json['latitude'], isNull);
    expect(json['isSimulated'], isTrue);
    expect(json['status'], 'alert_triggered');
    expect(json['riskScore'], 95);
  });
}

Incident _historyIncident({
  required String id,
  required String eventType,
  required int riskScore,
  required IncidentStatus status,
  required DateTime createdAt,
}) => Incident(
  id: id,
  detectionResult: DetectionResult(
    eventType: eventType,
    confidence: .9,
    impactDetected: riskScore >= 70,
    stillnessDetected: false,
    riskScore: riskScore,
    riskLevel: riskScore >= 70 ? RiskLevel.critical : RiskLevel.medium,
    detectedAt: createdAt,
  ),
  status: status,
  createdAt: createdAt,
  updatedAt: createdAt,
);

Future<void> _tapSimulateDistress(WidgetTester tester) async {
  final trigger = find.text('Demo: Simulate Distress');
  await tester.ensureVisible(trigger);
  await tester.pump();
  await tester.tap(trigger);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {});
  await tester.pumpAndSettle();
  expect(find.text('Preparing simulation…'), findsNothing);
}

class _FlakyIncidents extends InMemoryIncidentRepository {
  bool failLoad = false;
  bool failRemove = false;
  bool failUpdate = false;
  bool failSave = false;
  @override
  Future<Incident> save(Incident incident) async {
    if (failSave) throw StateError('Storage unavailable');
    return super.save(incident);
  }

  @override
  Future<List<Incident>> getAll() async {
    if (failLoad) throw StateError('Storage unavailable');
    return super.getAll();
  }

  @override
  Future<void> remove(String id) async {
    if (failRemove) throw StateError('Storage unavailable');
    return super.remove(id);
  }

  @override
  Future<Incident> update(Incident incident) async {
    if (failUpdate) throw StateError('Storage unavailable');
    return super.update(incident);
  }
}

class _FlakyContacts extends InMemoryTrustedContactRepository {
  _FlakyContacts() : super(seed: []);
  bool failLoad = false;
  bool failSave = false;
  bool failRemove = false;
  @override
  Future<List<TrustedContact>> getAll() async {
    if (failLoad) throw StateError('Storage unavailable');
    return super.getAll();
  }

  @override
  Future<TrustedContact> add(TrustedContact contact) async {
    if (failSave) throw StateError('Storage unavailable');
    return super.add(contact);
  }

  @override
  Future<void> remove(String id) async {
    if (failRemove) throw StateError('Storage unavailable');
    return super.remove(id);
  }
}

class _TestAlerts implements AlertService {
  bool failTest = false;
  bool failResponse = false;
  final responseIds = <String>[];
  @override
  String get deviceToken => 'synthetic-device-token-12345';
  @override
  Future<int> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async => contactTokens.length;
  @override
  Future<bool> sendTestMessage(String token) async {
    if (failTest) throw StateError('Relay unavailable');
    return true;
  }

  @override
  Future<void> sendResponse({
    required String recipientToken,
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  }) async {
    responseIds.add(incidentId);
    if (failResponse) throw StateError('Relay unavailable');
  }

  @override
  Future<void> cancelAlert(String incidentId) async {}
}

class _UnavailableLocation extends LocationService {
  @override
  Future<LocationSnapshot?> currentLocation({
    bool requestPermission = true,
  }) async {
    status = LocationStatus.denied;
    return null;
  }
}

Future<void> _pumpScenario(WidgetTester tester, DetectionScenario scenario) =>
    tester.pumpWidget(
      MaterialApp(
        home: MonitoringScreen(scenario: scenario),
        routes: {
          AppRoutes.monitoring: (_) => const MonitoringScreen(),
          AppRoutes.safetyCheck: (_) => const SafetyCheckScreen(),
          AppRoutes.emergencyAlert: (_) => const EmergencyAlertScreen(),
          AppRoutes.history: (_) => const HistoryScreen(),
        },
      ),
    );
