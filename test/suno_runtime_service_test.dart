import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/backend_exports.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/models/received_alert.dart';
import 'package:suno_ai/models/trusted_contact.dart';
import 'package:suno_ai/services/suno_runtime_service.dart';

void main() {
  SunoRuntimeService makeRuntime({
    SafetyCheckEngine? safety,
    IncidentRepository? incidents,
    FakeLocation? location,
    FakeAlerts? alerts,
  }) {
    final runtime = SunoRuntimeService(
      safetyCheckEngine: safety,
      incidentRepository: incidents,
      locationService: location ?? FakeLocation(),
      alertService: alerts,
      trustedContactRepository: InMemoryTrustedContactRepository(
        seed: const [
          TrustedContact(
            id: 'a',
            name: 'Test contact',
            phone: '',
            relationship: 'Friend',
            fcmToken: 'test-token-a',
          ),
          TrustedContact(
            id: 'b',
            name: 'Another contact',
            phone: '',
            relationship: 'Friend',
            fcmToken: 'test-token-b',
          ),
        ],
      ),
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  test(
    'Demo keeps all three risk outcomes and uses an injected GPS fix',
    () async {
      final runtime = makeRuntime();
      for (final scenario in DetectionScenario.values) {
        final detection = await runtime.runDetection(scenario);
        expect(detection.riskScore, [0, 50, 95][scenario.index]);
        expect(detection.riskLevel, RiskLevel.values[scenario.index]);
        expect(detection.isSimulated, isTrue);
        expect(detection.latitude, 33.6844);
        expect(detection.longitude, 73.0479);
        if (scenario == DetectionScenario.low) {
          expect(await runtime.recordDetection(detection), isNull);
        }
      }
    },
  );

  test(
    'failed GPS clears the previous fix and does not prevent an alert',
    () async {
      final location = FakeLocation();
      final alerts = FakeAlerts();
      final runtime = makeRuntime(location: location, alerts: alerts);
      await runtime.refreshLocation();
      location.available = false;
      final detection = await runtime.runDetection(DetectionScenario.critical);
      final incident = (await runtime.recordDetection(detection))!;
      await finishDispatch(runtime, incident.id);
      expect(runtime.location, isNull);
      expect(detection.latitude, isNull);
      expect(detection.locationText, isNull);
      expect(alerts.payloads.single.containsKey('latitude'), isFalse);
      expect(
        runtime.incidentById(incident.id)?.dispatchResult?.success,
        isTrue,
      );
    },
  );

  test(
    'alert payload and saved incident share the exact location snapshot',
    () async {
      final alerts = FakeAlerts();
      final runtime = makeRuntime(alerts: alerts);
      final incident = (await runtime.recordDetection(
        await runtime.runDetection(DetectionScenario.critical),
      ))!;
      await finishDispatch(runtime, incident.id);
      expect(
        alerts.payloads.single['latitude'],
        '${incident.detectionResult.latitude}',
      );
      expect(
        alerts.payloads.single['longitude'],
        '${incident.detectionResult.longitude}',
      );
      expect(alerts.payloads.single['isSimulated'], 'true');
    },
  );

  test('named Demo scenarios never call an injected Live repository', () async {
    final repository = CountingLiveRepository();
    final runtime = SunoRuntimeService(
      detectionEngine: DetectionEngine(repository: repository),
      locationService: FakeLocation(),
    );
    addTearDown(runtime.dispose);
    for (final scenario in DetectionScenario.values) {
      await runtime.runDetection(scenario);
    }
    expect(repository.calls, 0);
  });

  test('unknown risk strings throw instead of silently becoming LOW', () {
    expect(
      () => RiskLevelContract.fromWireValue('high'),
      throwsFormatException,
    );
  });

  test('medium countdown starts and escalates without any screen', () async {
    final runtime = makeRuntime(
      safety: SafetyCheckEngine(
        countdownDuration: const Duration(milliseconds: 10),
      ),
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.medium),
    ))!;
    expect(incident.safetyCheckDeadline, isNotNull);
    await runtime.safetyCheckCompleted;
    await finishDispatch(runtime, incident.id);
    expect(runtime.incidentById(incident.id)?.detectionResult.riskScore, 70);
    expect(
      runtime.incidentById(incident.id)?.detectionResult.isSimulated,
      isTrue,
    );
    expect(
      runtime.incidentById(incident.id)?.status,
      IncidentStatus.alertTriggered,
    );
  });

  test('safe confirmation cancels only the explicit safety incident', () async {
    final runtime = makeRuntime();
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.medium),
    ))!;
    runtime.confirmSafe('unrelated');
    expect(runtime.hasPendingSafetyCheck, isTrue);
    runtime.confirmSafe(incident.id);
    await runtime.safetyCheckCompleted;
    expect(runtime.currentIncident?.status, IncidentStatus.cancelled);
    expect(runtime.currentIncident?.contactResponseText, 'User confirmed safe');
  });

  test('immediate escalation does not need a safety screen', () async {
    final runtime = makeRuntime();
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.medium),
    ))!;
    runtime.escalateSafetyCheck(incident.id);
    await runtime.safetyCheckCompleted;
    await finishDispatch(runtime, incident.id);
    expect(
      runtime.currentIncident?.detectionResult.riskLevel,
      RiskLevel.critical,
    );
  });

  for (final safe in [true, false]) {
    test(
      'failed safety save retains ownership and retries (safe=$safe)',
      () async {
        final repository = FailingUpdateRepository();
        final alerts = FakeAlerts();
        final runtime = makeRuntime(incidents: repository, alerts: alerts);
        final incident = (await runtime.recordDetection(
          detection(RiskLevel.medium),
        ))!;
        repository.fail = true;
        if (safe) {
          runtime.confirmSafe(incident.id);
        } else {
          runtime.escalateSafetyCheck(incident.id);
        }
        await runtime.safetyCheckCompleted;
        expect(runtime.hasPendingSafetyCheck, isTrue);
        expect(runtime.safetyCheckNeedsRetry, isTrue);
        expect(runtime.currentIncident?.status, IncidentStatus.safetyCheck);
        expect(alerts.payloads, isEmpty);
        expect(
          (await runtime.recordDetection(detection(RiskLevel.critical)))?.id,
          incident.id,
        );
        await expectLater(
          runtime.removeIncident(incident.id),
          throwsStateError,
        );
        repository.fail = false;
        if (safe) {
          runtime.confirmSafe(incident.id);
        } else {
          runtime.escalateSafetyCheck(incident.id);
        }
        await runtime.safetyCheckCompleted;
        await finishDispatch(runtime, incident.id);
        expect(runtime.hasPendingSafetyCheck, isFalse);
        expect(runtime.safetyCheckNeedsRetry, isFalse);
        expect(runtime.operationError, isNull);
        expect(
          runtime.currentIncident?.status,
          safe ? IncidentStatus.cancelled : IncidentStatus.contactNotified,
        );
        expect(alerts.payloads.length, safe ? 0 : 1);
        expect(
          runtime.currentIncident?.safetyCheckDeadline,
          incident.safetyCheckDeadline,
        );
      },
    );
  }

  test('restored deadline is not restarted from ten seconds', () async {
    final repository = InMemoryIncidentRepository();
    final now = DateTime.now();
    await repository.save(
      Incident(
        id: 'restored',
        detectionResult: detection(RiskLevel.medium),
        status: IncidentStatus.safetyCheck,
        createdAt: now.subtract(const Duration(minutes: 1)),
        updatedAt: now,
        safetyCheckDeadline: now.subtract(const Duration(seconds: 1)),
      ),
    );
    final runtime = makeRuntime(incidents: repository);
    await runtime.restoreLatestIncident();
    await runtime.safetyCheckCompleted.timeout(const Duration(seconds: 1));
    await finishDispatch(runtime, 'restored');
    expect(runtime.currentIncident?.status, IncidentStatus.alertTriggered);
  });

  test(
    'duplicate detection and dispatch calls do not create or send twice',
    () async {
      final alerts = FakeAlerts()..pending = Completer<int>();
      final runtime = makeRuntime(alerts: alerts);
      final results = await Future.wait([
        runtime.recordDetection(detection(RiskLevel.critical)),
        runtime.recordDetection(detection(RiskLevel.critical)),
      ]);
      final id = results.first!.id;
      expect(results.last!.id, id);
      final first = runtime.dispatchIncident(id);
      final second = runtime.dispatchIncident(id);
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(alerts.payloads.length, 1);
      alerts.pending!.complete(1);
      await first;
      expect(
        runtime.incidentById(id)?.dispatchResult?.partiallyDelivered,
        isTrue,
      );
      expect(await runtime.getIncidentHistory(), hasLength(1));
    },
  );

  test('an old response never replaces the active outgoing incident', () async {
    final runtime = makeRuntime();
    final first = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, first.id);
    final second = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, second.id);
    await runtime.applyContactResponse(
      incidentId: first.id,
      responderName: 'Your contact',
      status: 'resolved',
      message: 'They are safe',
    );
    expect(runtime.incidentById(first.id)?.status, IncidentStatus.resolved);
    expect(runtime.currentIncident?.id, second.id);
    expect(runtime.currentIncident?.status, IncidentStatus.alertTriggered);
  });

  test(
    'received duplicates preserve resolution and outgoing selection',
    () async {
      final runtime = makeRuntime();
      final outgoing = (await runtime.recordDetection(
        detection(RiskLevel.critical),
      ))!;
      await finishDispatch(runtime, outgoing.id);
      final alert = ReceivedAlert.fromData({
        'incidentId': 'received',
        'eventType': 'Distress Sound',
        'riskScore': '95',
        'riskLevel': 'critical',
      });
      await runtime.acceptReceivedAlert(alert);
      await runtime.updateStatus(IncidentStatus.resolved, 'Safe', 'received');
      await runtime.acceptReceivedAlert(alert);
      expect(runtime.incidentById('received')?.status, IncidentStatus.resolved);
      expect(runtime.currentIncident?.id, outgoing.id);
      expect(await runtime.getIncidentHistory(), hasLength(2));
    },
  );

  test('late response cannot reopen a resolved outgoing incident', () async {
    final runtime = makeRuntime();
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);
    for (final status in ['resolved', 'contactChecking', 'alertTriggered']) {
      await runtime.applyContactResponse(
        incidentId: incident.id,
        responderName: 'Your contact',
        status: status,
        message: status,
      );
    }
    expect(runtime.incidentById(incident.id)?.status, IncidentStatus.resolved);
  });

  test('response failure or missing sender routing is not success', () async {
    final runtime = makeRuntime(alerts: FakeAlerts()..responseFails = true);
    await expectLater(
      runtime.sendResponse(
        recipientToken: '',
        incidentId: 'id',
        responderName: 'Your contact',
        status: 'resolved',
        message: 'Safe',
      ),
      throwsStateError,
    );
    await expectLater(
      runtime.sendResponse(
        recipientToken: 'sender',
        incidentId: 'id',
        responderName: 'Your contact',
        status: 'resolved',
        message: 'Safe',
      ),
      throwsStateError,
    );
  });

  test('deleted incoming incidents stay deleted when replayed after runtime restart', () async {
    final repository = InMemoryIncidentRepository();
    final runtime = makeRuntime(incidents: repository);
    final alert = ReceivedAlert.fromData({
      'incidentId': 'removed',
      'eventType': 'Distress Sound',
    });
    await runtime.acceptReceivedAlert(alert);
    await runtime.removeIncident('removed');
    final reopened = makeRuntime(incidents: repository);
    await reopened.restoreLatestIncident();
    expect(await reopened.acceptReceivedAlert(alert), isNull);
    expect(await reopened.getIncidentHistory(), isEmpty);
  });

  test(
    'repository upserts, sorts by createdAt, and returns immutable history',
    () async {
      final repository = InMemoryIncidentRepository();
      final now = DateTime.now();
      final newer = Incident(
        id: 'new',
        detectionResult: detection(RiskLevel.critical),
        status: IncidentStatus.resolved,
        createdAt: now,
        updatedAt: now,
      );
      final older = Incident(
        id: 'old',
        detectionResult: detection(RiskLevel.critical),
        status: IncidentStatus.resolved,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      );
      await repository.save(newer);
      await repository.save(older);
      await repository.save(newer);
      expect((await repository.latest())?.id, 'new');
      final history = await repository.getAll();
      expect(history, hasLength(2));
      expect(() => history.removeAt(0), throwsUnsupportedError);
    },
  );

  test('manual SOS bypasses Live inference and attaches GPS', () async {
    final runtime = makeRuntime();
    final incident = (await runtime.triggerManualAlert())!;
    await finishDispatch(runtime, incident.id);
    expect(incident.detectionResult.eventType, 'Manual Silent Alert');
    expect(incident.detectionResult.riskScore, 100);
    expect(incident.detectionResult.isSimulated, isFalse);
    expect(incident.detectionResult.latitude, 33.6844);
  });
}

Future<void> finishDispatch(SunoRuntimeService runtime, String id) async {
  if (runtime.isDispatching(id)) await runtime.dispatchIncident(id);
}

DetectionResult detection(RiskLevel risk) => DetectionResult(
  eventType: 'Distress Sound',
  confidence: .9,
  impactDetected: false,
  stillnessDetected: false,
  riskScore: risk == RiskLevel.medium ? 50 : 95,
  riskLevel: risk,
  isSimulated: true,
  detectedAt: DateTime.now(),
);

class FakeLocation extends LocationService {
  bool available = true;
  @override
  Future<LocationSnapshot?> currentLocation({
    bool requestPermission = true,
  }) async {
    status = available ? LocationStatus.ready : LocationStatus.denied;
    return available
        ? LocationSnapshot(
            latitude: 33.6844,
            longitude: 73.0479,
            capturedAt: DateTime.now(),
          )
        : null;
  }
}

class FakeAlerts implements AlertService {
  final payloads = <Map<String, String>>[];
  Completer<int>? pending;
  bool responseFails = false;
  @override
  String? get deviceToken => 'synthetic-sender';
  @override
  Future<int> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async {
    payloads.add(payload);
    return pending == null ? contactTokens.length : pending!.future;
  }

  @override
  Future<bool> sendTestMessage(String token) async => true;
  @override
  Future<void> cancelAlert(String incidentId) async {}
  @override
  Future<void> sendResponse({
    required String recipientToken,
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  }) async {
    if (responseFails) throw StateError('Synthetic response failure');
  }
}

class FailingUpdateRepository extends InMemoryIncidentRepository {
  bool fail = false;
  @override
  Future<Incident> update(Incident incident) async {
    if (fail) throw StateError('Storage unavailable');
    return super.update(incident);
  }
}

class CountingLiveRepository implements DetectionRepository {
  int calls = 0;
  @override
  Future<DetectionResult> detect() async {
    calls++;
    return detection(RiskLevel.critical);
  }
}
