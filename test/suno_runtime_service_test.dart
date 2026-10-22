import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/backend_exports.dart';
import 'package:suno_ai/backend/profile/locale_repository.dart';
import 'package:suno_ai/core/l10n/app_locales.dart';
import 'package:suno_ai/core/l10n/locale_controller.dart';
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
    FakeLocalAlarm? alarm,
    AlertOutbox? outbox,
  }) {
    final runtime = SunoRuntimeService(
      safetyCheckEngine: safety,
      incidentRepository: incidents,
      locationService: location ?? FakeLocation(),
      alertService: alerts,
      localAlarmService: alarm,
      alertOutbox: outbox,
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

  test('the safety countdown starts the alarm immediately', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeRuntime(
      safety: SafetyCheckEngine(
        countdownDuration: const Duration(seconds: 5),
      ),
      alarm: alarm,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.medium),
    ))!;
    expect(alarm.sounded, [incident.id]);
    // The native player stops itself after this duration, so a backgrounded
    // isolate cannot leave the alarm ringing past the countdown.
    expect(alarm.durations.single, isNotNull);
    expect(alarm.durations.single! <= const Duration(seconds: 5), isTrue);

    runtime.confirmSafe(incident.id);
    await runtime.safetyCheckCompleted;
    expect(alarm.stops, 1);
  });

  test('the alarm stops when the countdown expires on its own', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeRuntime(
      safety: SafetyCheckEngine(
        countdownDuration: const Duration(milliseconds: 40),
      ),
      alarm: alarm,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.medium),
    ))!;
    expect(alarm.sounded, [incident.id]);

    await runtime.safetyCheckCompleted;
    await finishDispatch(runtime, incident.id);
    expect(alarm.stops, greaterThanOrEqualTo(1));
  });

  test('the alarm stops when the person cannot respond', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeRuntime(
      safety: SafetyCheckEngine(
        countdownDuration: const Duration(seconds: 5),
      ),
      alarm: alarm,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.medium),
    ))!;
    expect(alarm.sounded, [incident.id]);

    runtime.escalateSafetyCheck(incident.id);
    await runtime.safetyCheckCompleted;
    await finishDispatch(runtime, incident.id);
    expect(alarm.stops, greaterThanOrEqualTo(1));
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

  test('restored deadline is not restarted from the full countdown', () async {
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
      final alerts = FakeAlerts()..pending = Completer<Set<String>>();
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
      alerts.pending!.complete({'test-token-a'});
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

  test(
    'received alerts keep the receiver\'s own label when the token matches',
    () async {
      final runtime = makeRuntime();
      await runtime.acceptReceivedAlert(
        ReceivedAlert.fromData({
          'incidentId': 'matched',
          'eventType': 'Distress Sound',
          'riskLevel': 'critical',
          'senderToken': 'test-token-a',
          'senderName': 'Whoever The Sender Claimed',
        }),
      );
      expect(runtime.incidentById('matched')?.senderName, 'Test contact');
    },
  );

  test(
    'an unknown token falls back to the sender name in the payload',
    () async {
      final runtime = makeRuntime();
      await runtime.acceptReceivedAlert(
        ReceivedAlert.fromData({
          'incidentId': 'payload-name',
          'eventType': 'Distress Sound',
          'riskLevel': 'critical',
          'senderToken': 'not-a-contact-token',
          'senderName': 'Rayyan',
        }),
      );
      expect(runtime.incidentById('payload-name')?.senderName, 'Rayyan');
    },
  );

  test('an alert with no name anywhere stores null', () async {
    final runtime = makeRuntime();
    await runtime.acceptReceivedAlert(
      ReceivedAlert.fromData({
        'incidentId': 'nameless',
        'eventType': 'Distress Sound',
        'riskLevel': 'critical',
      }),
    );
    expect(runtime.incidentById('nameless')?.senderName, isNull);
  });

  test('payload names are cleaned of control characters and capped', () async {
    final runtime = makeRuntime();
    await runtime.acceptReceivedAlert(
      ReceivedAlert.fromData({
        'incidentId': 'control',
        'eventType': 'Distress Sound',
        'senderName': 'Ayan\u0000\nKhan',
      }),
    );
    expect(runtime.incidentById('control')?.senderName, 'Ayan Khan');
    await runtime.acceptReceivedAlert(
      ReceivedAlert.fromData({
        'incidentId': 'lengthy',
        'eventType': 'Distress Sound',
        'senderName': 'a' * 200,
      }),
    );
    expect(runtime.incidentById('lengthy')?.senderName?.length, 64);
  });

  test(
    'outgoing alerts carry the saved name and omit the key when unset',
    () async {
      final alerts = FakeAlerts();
      final runtime = makeRuntime(alerts: alerts);
      final unnamed = (await runtime.recordDetection(
        detection(RiskLevel.critical),
      ))!;
      await finishDispatch(runtime, unnamed.id);
      expect(alerts.payloads.single.containsKey('senderName'), isFalse);

      await runtime.saveMyName('Ayan');
      expect(await runtime.getMyName(), 'Ayan');
      final named = (await runtime.recordDetection(
        detection(RiskLevel.critical),
      ))!;
      await finishDispatch(runtime, named.id);
      expect(alerts.payloads.last['senderName'], 'Ayan');
    },
  );

  test(
    'outgoing alerts carry the chosen language in both wire keys',
    () async {
      final controller = LocaleController(
        repository: InMemoryLocaleRepository(),
      );
      await controller.setLanguage(SunoLanguages.spanish);
      LocaleController.instance = controller;
      addTearDown(() {
        LocaleController.instance = LocaleController(
          repository: InMemoryLocaleRepository(),
        );
      });
      final alerts = FakeAlerts();
      final runtime = makeRuntime(alerts: alerts);
      final incident = (await runtime.recordDetection(
        detection(RiskLevel.critical),
      ))!;
      await finishDispatch(runtime, incident.id);
      expect(alerts.payloads.single['lang'], 'es');
      expect(alerts.payloads.single['languageCode'], 'es');
      expect(alerts.payloads.single.length, lessThanOrEqualTo(16));
    },
  );

  test(
    'a received alert stores the sender language and drops unknown codes',
    () async {
      final runtime = makeRuntime();
      for (final data in [
        {'incidentId': 'new', 'lang': 'es'},
        {'incidentId': 'legacy', 'languageCode': 'fr'},
        {'incidentId': 'unsupported', 'lang': 'pt'},
        {'incidentId': 'blank', 'lang': '  '},
      ]) {
        await runtime.acceptReceivedAlert(
          ReceivedAlert.fromData({...data, 'eventType': 'Distress Sound'}),
        );
      }
      expect(runtime.incidentById('new')?.senderLang, 'es');
      expect(runtime.incidentById('legacy')?.senderLang, 'fr');
      expect(runtime.incidentById('unsupported')?.senderLang, isNull);
      expect(runtime.incidentById('blank')?.senderLang, isNull);
      await runtime.updateStatus(IncidentStatus.resolved, 'Safe', 'new');
      expect(runtime.incidentById('new')?.senderLang, 'es');
    },
  );

  test(
    'a reply forwards the banner language and omits it when unknown',
    () async {
      final alerts = FakeAlerts();
      final runtime = makeRuntime(alerts: alerts);
      await runtime.sendResponse(
        recipientToken: 'synthetic-sender-token',
        incidentId: 'spanish-sender',
        responderName: 'Ayan',
        status: 'resolved',
        message: 'Están a salvo',
        recipientLang: 'es',
      );
      expect(alerts.responses.single.lang, 'es');
      await runtime.sendResponse(
        recipientToken: 'synthetic-sender-token',
        incidentId: 'legacy-sender',
        responderName: 'Ayan',
        status: 'resolved',
        message: 'They are safe',
      );
      expect(alerts.responses.last.lang, isNull);
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

  /// A contact that has both a push token and a number, so either channel can
  /// be observed on the same incident.
  SunoRuntimeService makeDualChannelRuntime({
    required FakeAlerts alerts,
    required Map<String, String> dialed,
    FakeLocalAlarm? alarm,
    bool smsDelivers = true,
    AlertOutbox? outbox,
  }) {
    final runtime = SunoRuntimeService(
      alertService: alerts,
      locationService: FakeLocation(),
      localAlarmService: alarm,
      alertOutbox: outbox,
      smsFallbackService: SmsFallbackService(
        send: ({required phoneNumber, required message}) async {
          if (!smsDelivers) return false;
          dialed[phoneNumber] = message;
          return true;
        },
      ),
      trustedContactRepository: InMemoryTrustedContactRepository(
        seed: const [
          TrustedContact(
            id: 'a',
            name: 'Test contact',
            phone: '+92 300-123-4567',
            relationship: 'Friend',
            fcmToken: 'test-token-a',
          ),
        ],
      ),
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  /// A runtime with an arbitrary contact list and a recording SMS sender.
  SunoRuntimeService makeContactRuntime({
    required FakeAlerts? alerts,
    required List<TrustedContact> contacts,
    Map<String, String>? dialed,
    FakeLocalAlarm? alarm,
    bool smsDelivers = true,
    AlertOutbox? outbox,
  }) {
    final runtime = SunoRuntimeService(
      alertService: alerts,
      locationService: FakeLocation(),
      localAlarmService: alarm,
      alertOutbox: outbox,
      smsFallbackService: SmsFallbackService(
        send: ({required phoneNumber, required message}) async {
          if (!smsDelivers) return false;
          dialed?[phoneNumber] = message;
          return true;
        },
      ),
      trustedContactRepository: InMemoryTrustedContactRepository(
        seed: contacts,
      ),
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  test(
    'an unreachable relay falls back to SMS and queues the push half',
    () async {
      final alerts = FakeAlerts()..sendFails = true;
      final dialed = <String, String>{};
      final outbox = InMemoryAlertOutbox();
      final runtime = makeDualChannelRuntime(
        alerts: alerts,
        dialed: dialed,
        outbox: outbox,
      );
      final incident = (await runtime.recordDetection(
        detection(RiskLevel.critical),
      ))!;
      await finishDispatch(runtime, incident.id);

      expect(dialed.keys, ['+923001234567']);
      expect(dialed.values.single, contains('Distress Sound'));
      final delivered = runtime.incidentById(incident.id)!;
      expect(delivered.dispatchResult?.sentCount, 0);
      expect(delivered.dispatchResult?.smsSentCount, 1);
      expect(delivered.dispatchResult?.usedSmsFallback, isTrue);
      // Android accepted the SMS, but submission is not relay-confirmed push
      // delivery, so this must not be reported as "reached".
      expect(delivered.dispatchResult?.success, isFalse);
      expect(delivered.dispatchResult?.queued, isTrue);
      expect(delivered.status, IncidentStatus.alertTriggered);
      expect((await outbox.getAll()).single.incidentId, incident.id);
    },
  );

  test(
    'no internet and a rejected SMS is saved, not reported as reached',
    () async {
      final alerts = FakeAlerts()..sendFails = true;
      final alarm = FakeLocalAlarm();
      final outbox = InMemoryAlertOutbox();
      final runtime = makeDualChannelRuntime(
        alerts: alerts,
        dialed: {},
        smsDelivers: false,
        alarm: alarm,
        outbox: outbox,
      );
      final incident = (await runtime.recordDetection(
        detection(RiskLevel.critical),
      ))!;
      await finishDispatch(runtime, incident.id);

      final failed = runtime.incidentById(incident.id)!;
      expect(failed.dispatchResult?.success, isFalse);
      expect(failed.dispatchResult?.sentCount, 0);
      expect(failed.dispatchResult?.smsSentCount, 0);
      expect(failed.dispatchResult?.totalDelivered, 0);
      expect(failed.dispatchResult?.queued, isTrue);
      expect(failed.status, IncidentStatus.alertTriggered);
      expect(alarm.sounded, [incident.id]);
      expect((await outbox.getAll()).single.incidentId, incident.id);

      // The saved half is pushed once the relay is reachable again; the phone
      // never pretends the failed SMS was delivered.
      alerts.sendFails = false;
      await runtime.retryPendingAlerts();
      expect(await outbox.getAll(), isEmpty);
      final delivered = runtime.incidentById(incident.id)!;
      expect(delivered.dispatchResult?.sentCount, 1);
      expect(delivered.dispatchResult?.success, isTrue);
      expect(delivered.status, IncidentStatus.contactNotified);
    },
  );

  test('a queued alert is sent automatically when the relay returns', () async {
    final alerts = FakeAlerts()..sendFails = true;
    final outbox = InMemoryAlertOutbox();
    final runtime = makeDualChannelRuntime(
      alerts: alerts,
      dialed: {},
      outbox: outbox,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);
    expect(runtime.incidentById(incident.id)!.dispatchResult!.queued, isTrue);
    expect(alerts.payloads, hasLength(1));

    alerts.sendFails = false;
    await runtime.retryPendingAlerts();

    expect(alerts.payloads, hasLength(2));
    expect(alerts.payloads.last['incidentId'], incident.id);
    expect(await outbox.getAll(), isEmpty);
    final delivered = runtime.incidentById(incident.id)!;
    expect(delivered.dispatchResult?.sentCount, 1);
    expect(delivered.dispatchResult?.success, isTrue);
    expect(delivered.dispatchResult?.queued, isFalse);
    expect(delivered.status, IncidentStatus.contactNotified);
  });

  test('a relay that answers "no" is not retried forever', () async {
    final alerts = FakeAlerts()..acceptedSubset = <String>{};
    final outbox = InMemoryAlertOutbox();
    final runtime = makeDualChannelRuntime(
      alerts: alerts,
      dialed: {},
      outbox: outbox,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    final result = runtime.incidentById(incident.id)!.dispatchResult!;
    expect(result.success, isFalse);
    expect(result.queued, isFalse);
    expect(await outbox.getAll(), isEmpty);
  });

  test('resolving an incident drops its queued alert', () async {
    final alerts = FakeAlerts()..sendFails = true;
    final outbox = InMemoryAlertOutbox();
    final runtime = makeContactRuntime(
      alerts: alerts,
      outbox: outbox,
      contacts: const [
        TrustedContact(
          id: 'token-only',
          name: 'Token only',
          phone: '',
          relationship: 'Friend',
          fcmToken: 'test-token-a',
        ),
      ],
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);
    expect(await outbox.getAll(), hasLength(1));

    await runtime.updateStatus(IncidentStatus.resolved, null, incident.id);
    expect(await outbox.getAll(), isEmpty);
  });

  test('a fully delivered push alert does not also send an SMS', () async {
    final dialed = <String, String>{};
    final runtime = makeDualChannelRuntime(
      alerts: FakeAlerts(),
      dialed: dialed,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    expect(dialed, isEmpty);
    final delivered = runtime.incidentById(incident.id)!;
    expect(delivered.dispatchResult?.sentCount, 1);
    expect(delivered.dispatchResult?.usedSmsFallback, isFalse);
    expect(delivered.status, IncidentStatus.contactNotified);
  });

  test('a dispatch that reaches nobody alarms the phone itself', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeDualChannelRuntime(
      alerts: FakeAlerts()..sendFails = true,
      dialed: {},
      alarm: alarm,
      smsDelivers: false,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    expect(alarm.sounded, [incident.id]);
    final stalled = runtime.incidentById(incident.id)!.dispatchResult!;
    expect(stalled.totalDelivered, 0);

    await runtime.updateStatus(IncidentStatus.resolved, null, incident.id);
    expect(alarm.stops, 1);
  });

  test('an alarm stays silent while contacts are reached', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeDualChannelRuntime(
      alerts: FakeAlerts(),
      dialed: {},
      alarm: alarm,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    expect(alarm.sounded, isEmpty);
  });

  test('a contact with a phone but no token is reached by SMS', () async {
    final dialed = <String, String>{};
    final runtime = makeContactRuntime(
      alerts: FakeAlerts(),
      dialed: dialed,
      contacts: const [
        TrustedContact(
          id: 'phone-only',
          name: 'Phone only',
          phone: '+92 300-123-4567',
          relationship: 'Friend',
        ),
      ],
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    expect(dialed.keys, ['+923001234567']);
    final result = runtime.incidentById(incident.id)!.dispatchResult!;
    expect(result.attemptedCount, 1);
    expect(result.sentCount, 0);
    expect(result.smsSentCount, 1);
    expect(result.success, isFalse);
    expect(runtime.incidentById(incident.id)!.status, IncidentStatus.alertTriggered);
  });

  test('with no push service, a phone-only contact still gets SMS', () async {
    final dialed = <String, String>{};
    final runtime = makeContactRuntime(
      alerts: null,
      dialed: dialed,
      contacts: const [
        TrustedContact(
          id: 'phone-only',
          name: 'Phone only',
          phone: '+92 300-123-4567',
          relationship: 'Friend',
        ),
      ],
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    expect(dialed.keys, ['+923001234567']);
    final result = runtime.incidentById(incident.id)!.dispatchResult!;
    expect(result.attemptedCount, 1);
    expect(result.smsSentCount, 1);
    expect(result.success, isFalse);
    expect(result.queued, isFalse);
  });

  test('a launch without a push service still saves the alert for later', () async {
    final outbox = InMemoryAlertOutbox();
    final runtime = makeContactRuntime(
      alerts: null,
      alarm: FakeLocalAlarm(),
      outbox: outbox,
      contacts: const [
        TrustedContact(
          id: 'token-only',
          name: 'Token only',
          phone: '',
          relationship: 'Friend',
          fcmToken: 'test-token-a',
        ),
      ],
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    // Firebase can fail to start when the app launches offline; the token is
    // still worth saving because the next launch can deliver this alert.
    final result = runtime.incidentById(incident.id)!.dispatchResult!;
    expect(result.queued, isTrue);
    expect(result.success, isFalse);
    expect((await outbox.getAll()).single.incidentId, incident.id);
  });

  test('an unreachable contact still alarms the phone itself', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeContactRuntime(
      alerts: FakeAlerts(),
      alarm: alarm,
      contacts: const [
        TrustedContact(
          id: 'unreachable',
          name: 'No channel',
          phone: '',
          relationship: 'Friend',
        ),
      ],
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    expect(alarm.sounded, [incident.id]);
    final result = runtime.incidentById(incident.id)!.dispatchResult!;
    expect(result.attemptedCount, 1);
    expect(result.totalDelivered, 0);
    expect(result.success, isFalse);
    expect(runtime.incidentById(incident.id)!.status, IncidentStatus.alertTriggered);
  });

  test('a partial push sends SMS only to the contact push missed', () async {
    final alerts = FakeAlerts()..acceptedSubset = {'test-token-a'};
    final dialed = <String, String>{};
    final runtime = makeContactRuntime(
      alerts: alerts,
      dialed: dialed,
      contacts: const [
        TrustedContact(
          id: 'a',
          name: 'Reached by push',
          phone: '+92 300-000-0001',
          relationship: 'Friend',
          fcmToken: 'test-token-a',
        ),
        TrustedContact(
          id: 'b',
          name: 'Missed by push',
          phone: '+92 300-000-0002',
          relationship: 'Friend',
          fcmToken: 'test-token-b',
        ),
      ],
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);

    expect(dialed.keys, ['+923000000002']);
    final result = runtime.incidentById(incident.id)!.dispatchResult!;
    expect(result.attemptedCount, 2);
    expect(result.sentCount, 1);
    expect(result.smsSentCount, 1);
    expect(result.success, isFalse);
    expect(result.queued, isFalse);
    expect(
      runtime.incidentById(incident.id)!.status,
      IncidentStatus.contactNotified,
    );
  });

  test('a contact resolving remotely stops the local alarm', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeDualChannelRuntime(
      alerts: FakeAlerts()..sendFails = true,
      dialed: {},
      alarm: alarm,
      smsDelivers: false,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);
    expect(alarm.sounded, [incident.id]);
    expect(alarm.stops, 0);

    final applied = await runtime.applyContactResponse(
      incidentId: incident.id,
      responderName: 'Your contact',
      status: 'resolved',
      message: 'They are safe',
    );

    expect(applied, isTrue);
    expect(alarm.stops, 1);
    expect(runtime.incidentById(incident.id)?.status, IncidentStatus.resolved);
  });

  test('a contactChecking response does not stop the alarm', () async {
    final alarm = FakeLocalAlarm();
    final runtime = makeDualChannelRuntime(
      alerts: FakeAlerts()..sendFails = true,
      dialed: {},
      alarm: alarm,
      smsDelivers: false,
    );
    final incident = (await runtime.recordDetection(
      detection(RiskLevel.critical),
    ))!;
    await finishDispatch(runtime, incident.id);
    expect(alarm.sounded, [incident.id]);

    final applied = await runtime.applyContactResponse(
      incidentId: incident.id,
      responderName: 'Your contact',
      status: 'contactChecking',
      message: 'Checking on you',
    );

    expect(applied, isTrue);
    expect(alarm.stops, 0);
    expect(
      runtime.incidentById(incident.id)?.status,
      IncidentStatus.contactChecking,
    );
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
    Duration timeLimit = const Duration(seconds: 10),
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
  final responses =
      <({String incidentId, String message, String? lang})>[];
  Completer<Set<String>>? pending;
  Set<String>? acceptedSubset;
  bool responseFails = false;
  bool sendFails = false;
  @override
  String? get deviceToken => 'synthetic-sender';
  @override
  Future<Set<String>> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async {
    payloads.add(payload);
    if (sendFails) throw StateError('Synthetic relay failure');
    if (pending != null) return pending!.future;
    final all = contactTokens.toSet();
    final subset = acceptedSubset;
    return subset == null ? all : all.intersection(subset);
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
    String? recipientLang,
  }) async {
    responses.add(
      (incidentId: incidentId, message: message, lang: recipientLang),
    );
    if (responseFails) throw StateError('Synthetic response failure');
  }
}

/// Records the last-resort alarm instead of posting a real notification.
class FakeLocalAlarm extends LocalAlarmService {
  FakeLocalAlarm();

  final sounded = <String>[];
  final durations = <Duration?>[];
  int stops = 0;

  @override
  Future<void> sound({required String incidentId, Duration? duration}) async {
    sounded.add(incidentId);
    durations.add(duration);
  }

  @override
  Future<void> stop() async {
    stops++;
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
