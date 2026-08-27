import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/backend_exports.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/models/trusted_contact.dart';
import 'package:suno_ai/services/suno_runtime_service.dart';

void main() {
  test(
    'runtime demo scenarios preserve LOW MEDIUM CRITICAL outcomes',
    () async {
      final runtime = SunoRuntimeService();

      final low = await runtime.runDetection(DetectionScenario.low);
      expect(low.eventType, 'Ambient Sound');
      expect(low.riskScore, 0);
      expect(low.riskLevel, RiskLevel.low);
      expect(await runtime.recordDetection(low), isNull);
      expect(runtime.currentIncident, isNull);

      final medium = await runtime.runDetection(DetectionScenario.medium);
      final mediumIncident = await runtime.recordDetection(medium);
      expect(medium.eventType, 'Possible Distress Sound');
      expect(medium.riskScore, 50);
      expect(medium.riskLevel, RiskLevel.medium);
      expect(mediumIncident?.status, IncidentStatus.safetyCheck);

      final critical = await runtime.runDetection(DetectionScenario.critical);
      final criticalIncident = await runtime.recordDetection(critical);
      expect(critical.eventType, 'Distress Sound + Impact');
      expect(critical.riskScore, 95);
      expect(critical.riskLevel, RiskLevel.critical);
      expect(criticalIncident?.status, IncidentStatus.alertTriggered);
    },
  );

  test(
    'named demo scenarios stay frozen when a live repository is injected',
    () async {
      final engine = DetectionEngine(repository: _LiveCriticalRepository());
      final runtime = SunoRuntimeService(detectionEngine: engine);

      final low = await runtime.runDetection(DetectionScenario.low);
      final medium = await runtime.runDetection(DetectionScenario.medium);
      final critical = await runtime.runDetection(DetectionScenario.critical);
      final live = await engine.detect();

      expect(low.riskLevel, RiskLevel.low);
      expect(low.riskScore, 0);
      expect(medium.riskLevel, RiskLevel.medium);
      expect(medium.riskScore, 50);
      expect(critical.riskLevel, RiskLevel.critical);
      expect(critical.riskScore, 95);
      expect(live.eventType, 'Live Detector Event');
      expect(live.riskScore, 100);
    },
  );

  test('RiskLevel contract exposes only current demo readiness levels', () {
    expect(RiskLevel.values.map((level) => level.wireValue), [
      'low',
      'medium',
      'critical',
    ]);
    expect(RiskLevelContract.fromWireValue('high'), RiskLevel.low);
  });

  test(
    'SafetyCheckEngine timeout escalates medium detection to critical',
    () async {
      final runtime = SunoRuntimeService(
        safetyCheckEngine: SafetyCheckEngine(
          countdownDuration: const Duration(milliseconds: 5),
        ),
      );
      final medium = await runtime.runDetection(DetectionScenario.medium);
      await runtime.recordDetection(medium);

      final outcome = await runtime.startSafetyCheck();
      await runtime.applySafetyCheckResult(outcome);

      expect(outcome.outcome, SafetyCheckOutcome.noResponse);
      expect(outcome.detectionResult.riskScore, 70);
      expect(outcome.detectionResult.riskLevel, RiskLevel.critical);
      expect(runtime.currentIncident?.status, IncidentStatus.alertTriggered);
    },
  );

  test(
    'CAN\'T RESPOND immediately escalates the active safety check',
    () async {
      final runtime = SunoRuntimeService(
        safetyCheckEngine: SafetyCheckEngine(
          countdownDuration: const Duration(seconds: 1),
        ),
      );
      final medium = await runtime.runDetection(DetectionScenario.medium);
      await runtime.recordDetection(medium);

      final future = runtime.startSafetyCheck();
      runtime.escalateSafetyCheck();
      final outcome = await future;
      await runtime.applySafetyCheckResult(outcome);

      expect(outcome.outcome, SafetyCheckOutcome.noResponse);
      expect(outcome.detectionResult.riskLevel, RiskLevel.critical);
      expect(runtime.currentIncident?.status, IncidentStatus.alertTriggered);
    },
  );

  test('I AM SAFE resolves the safety check as cancelled', () async {
    final runtime = SunoRuntimeService(
      safetyCheckEngine: SafetyCheckEngine(
        countdownDuration: const Duration(seconds: 1),
      ),
    );
    final medium = await runtime.runDetection(DetectionScenario.medium);
    await runtime.recordDetection(medium);

    final future = runtime.startSafetyCheck();
    runtime.confirmSafe();
    final outcome = await future;
    await runtime.applySafetyCheckResult(outcome);

    expect(outcome.outcome, SafetyCheckOutcome.userConfirmedSafe);
    expect(outcome.detectionResult.riskScore, 50);
    expect(runtime.currentIncident?.status, IncidentStatus.cancelled);
    expect(runtime.currentIncident?.contactResponseText, 'User confirmed safe');
  });

  test(
    'SafetyCheckEngine disposal resolves the pending future as cancelled',
    () async {
      final detection = DetectionResult(
        eventType: 'Distress scream',
        confidence: 0.85,
        impactDetected: false,
        stillnessDetected: false,
        riskScore: 50,
        riskLevel: RiskLevel.medium,
        latitude: 31.5204,
        longitude: 74.3587,
        locationText: 'Lahore, Pakistan',
        detectedAt: DateTime(2026, 1, 1, 12),
      );
      final engine = SafetyCheckEngine(
        countdownDuration: const Duration(seconds: 1),
      );

      final future = engine.startCountdown(detection);
      engine.dispose();
      final outcome = await future;

      expect(outcome.outcome, SafetyCheckOutcome.cancelled);
      expect(outcome.detectionResult, detection);
    },
  );

  test('starting a new countdown cancels the previous check safely', () async {
    final firstDetection = DetectionResult(
      eventType: 'First safety check',
      confidence: 0.85,
      impactDetected: false,
      stillnessDetected: false,
      riskScore: 50,
      riskLevel: RiskLevel.medium,
      detectedAt: DateTime(2026, 1, 1, 12),
    );
    final secondDetection = DetectionResult(
      eventType: 'Second safety check',
      confidence: 0.85,
      impactDetected: false,
      stillnessDetected: false,
      riskScore: 50,
      riskLevel: RiskLevel.medium,
      detectedAt: DateTime(2026, 1, 1, 12, 1),
    );
    final engine = SafetyCheckEngine(
      countdownDuration: const Duration(seconds: 1),
    );

    final firstFuture = engine.startCountdown(firstDetection);
    final secondFuture = engine.startCountdown(secondDetection);
    final firstOutcome = await firstFuture;

    expect(firstOutcome.outcome, SafetyCheckOutcome.cancelled);
    expect(firstOutcome.detectionResult, same(firstDetection));
    expect(firstOutcome.detectionResult.riskScore, 50);
    expect(firstOutcome.detectionResult.riskLevel, RiskLevel.medium);

    engine.confirmSafe();
    final secondOutcome = await secondFuture;
    expect(secondOutcome.outcome, SafetyCheckOutcome.userConfirmedSafe);
    expect(secondOutcome.detectionResult, same(secondDetection));
  });

  test(
    'completed safety checks ignore late lifecycle actions and can restart',
    () async {
      final detection = DetectionResult(
        eventType: 'Possible Distress Sound',
        confidence: 0.85,
        impactDetected: false,
        stillnessDetected: false,
        riskScore: 50,
        riskLevel: RiskLevel.medium,
        detectedAt: DateTime(2026, 1, 1, 12),
      );
      final engine = SafetyCheckEngine(
        countdownDuration: const Duration(milliseconds: 5),
      );

      final timedOut = await engine.startCountdown(detection);
      engine.confirmSafe();
      engine.escalateNow();
      engine.dispose();

      expect(timedOut.outcome, SafetyCheckOutcome.noResponse);
      expect(timedOut.detectionResult.riskScore, 70);
      expect(timedOut.detectionResult.riskLevel, RiskLevel.critical);

      final restartedFuture = engine.startCountdown(detection);
      engine.confirmSafe();
      final restarted = await restartedFuture;

      expect(restarted.outcome, SafetyCheckOutcome.userConfirmedSafe);
      expect(restarted.detectionResult, same(detection));
    },
  );

  test('a cancelled safety check leaves the incident unchanged', () async {
    final runtime = SunoRuntimeService(
      safetyCheckEngine: SafetyCheckEngine(
        countdownDuration: const Duration(seconds: 1),
      ),
    );
    final medium = await runtime.runDetection(DetectionScenario.medium);
    final incident = await runtime.recordDetection(medium);

    final future = runtime.startSafetyCheck();
    runtime.cancelSafetyCheck();
    final outcome = await future;
    final unchanged = await runtime.applySafetyCheckResult(outcome);

    expect(outcome.outcome, SafetyCheckOutcome.cancelled);
    expect(unchanged, same(incident));
    expect(unchanged?.status, IncidentStatus.safetyCheck);
    expect(unchanged?.detectionResult, same(medium));
  });

  test(
    'incident repository preserves createdAt and updates status/history',
    () async {
      final repository = InMemoryIncidentRepository();
      final runtime = SunoRuntimeService(incidentRepository: repository);
      final critical = await runtime.runDetection(DetectionScenario.critical);
      final saved = await runtime.recordDetection(critical);
      expect(saved, isNotNull);

      final createdAt = saved!.createdAt;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final updated = await runtime.updateStatus(
        IncidentStatus.contactChecking,
        'Contact checking — help is on the way',
      );

      expect(updated?.id, saved.id);
      expect(updated?.createdAt, createdAt);
      expect(updated!.updatedAt.isAfter(createdAt), isTrue);
      expect(updated.status, IncidentStatus.contactChecking);
      expect(
        updated.contactResponseText,
        'Contact checking — help is on the way',
      );

      final history = await runtime.getIncidentHistory();
      expect(history, hasLength(1));
      expect(history.single.id, saved.id);
      expect(history.single.status, IncidentStatus.contactChecking);
    },
  );

  test(
    'incident repository supports multiple incidents in reverse-created order',
    () async {
      final repository = InMemoryIncidentRepository();
      final runtime = SunoRuntimeService(incidentRepository: repository);

      final first = await runtime.runDetection(DetectionScenario.medium);
      final firstIncident = await runtime.recordDetection(first);
      final second = await runtime.runDetection(DetectionScenario.critical);
      final secondIncident = await runtime.recordDetection(second);

      final history = await runtime.getIncidentHistory();
      expect(history, hasLength(2));
      expect(history.first.id, secondIncident!.id);
      expect(history.last.id, firstIncident!.id);
    },
  );

  test(
    'trusted contact responses persist the expected incident statuses',
    () async {
      final runtime = SunoRuntimeService();
      final critical = await runtime.runDetection(DetectionScenario.critical);
      await runtime.recordDetection(critical);

      await runtime.updateStatus(
        IncidentStatus.contactChecking,
        'Contact checking — help is on the way',
      );
      expect(runtime.currentIncident?.status, IncidentStatus.contactChecking);

      await runtime.updateStatus(
        IncidentStatus.resolved,
        'Resolved — contact confirmed they are safe',
      );
      expect(runtime.currentIncident?.status, IncidentStatus.resolved);

      await runtime.updateStatus(
        IncidentStatus.alertTriggered,
        'Unable to contact — emergency remains active',
      );
      expect(runtime.currentIncident?.status, IncidentStatus.alertTriggered);
      expect(
        runtime.currentIncident?.contactResponseText,
        'Unable to contact — emergency remains active',
      );
    },
  );

  test('runtime exposes contacts from trusted contact repository', () async {
    final contacts = await SunoRuntimeService().getTrustedContacts();
    expect(contacts, hasLength(1));
    expect(contacts.single.relationship, 'Brother');
  });

  test('runtime can add a trusted contact through its repository', () async {
    final contact = TrustedContact(
      id: 'contact-2',
      name: 'Demo Contact',
      phone: '+92 301 1111111',
      relationship: 'Friend',
    );
    final repository = InMemoryTrustedContactRepository();
    final runtime = SunoRuntimeService(trustedContactRepository: repository);

    await runtime.addTrustedContact(contact);
    final contacts = await runtime.getTrustedContacts();

    expect(contacts, hasLength(2));
    expect(contacts.last.id, contact.id);
  });
}

class _LiveCriticalRepository implements DetectionRepository {
  @override
  Future<DetectionResult> detect() async => DetectionResult(
    eventType: 'Live Detector Event',
    confidence: 0.99,
    impactDetected: true,
    stillnessDetected: true,
    riskScore: 100,
    riskLevel: RiskLevel.critical,
    detectedAt: DateTime(2026, 1, 1, 12),
  );
}
