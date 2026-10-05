import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/core/navigation/alert_navigation.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/services/alert_surfacing.dart';

void main() {
  final now = DateTime(2026, 9, 21, 12);

  Incident? pick(
    Iterable<Incident> incidents, {
    Set<String> surfaced = const {},
    DateTime? at,
    Duration? window,
  }) => pickUnseenReceivedAlert(
    incidents,
    now: at ?? now,
    alreadySurfaced: surfaced,
    window: window ?? unseenAlertWindow,
  );

  group('pickUnseenReceivedAlert', () {
    test('returns null when nothing is stored', () {
      expect(pick(const <Incident>[]), isNull);
    });

    test('picks an unanswered critical received alert', () {
      final incident = _received('fresh', updatedAt: now.subtract(const Duration(minutes: 2)));
      expect(pick([incident])!.id, 'fresh');
    });

    test('picks the newest of several qualifying alerts', () {
      final older = _received('older', updatedAt: now.subtract(const Duration(minutes: 8)));
      final newer = _received('newer', updatedAt: now.subtract(const Duration(minutes: 1)));
      expect(pick([older, newer])!.id, 'newer');
      expect(pick([newer, older])!.id, 'newer');
    });

    test('ignores incidents the user created themselves', () {
      expect(
        pick([_received('own', origin: 'self')]),
        isNull,
      );
    });

    test('ignores medium and low alerts', () {
      expect(pick([_received('medium', riskLevel: RiskLevel.medium)]), isNull);
      expect(pick([_received('low', riskLevel: RiskLevel.low)]), isNull);
    });

    test('ignores alerts that are no longer awaiting a response', () {
      for (final status in [
        IncidentStatus.resolved,
        IncidentStatus.contactChecking,
        IncidentStatus.contactNotified,
        IncidentStatus.cancelled,
      ]) {
        expect(
          pick([_received('done', status: status)]),
          isNull,
          reason: '$status must not resurface',
        );
      }
    });

    test('ignores alerts the receiver already answered', () {
      expect(
        pick([_received('answered', contactResponseText: 'They are safe')]),
        isNull,
      );
    });

    test('ignores alerts already surfaced in this session', () {
      expect(pick([_received('shown')], surfaced: const {'shown'}), isNull);
      // A different id is still surfaced.
      expect(pick([_received('shown')], surfaced: const {'other'})!.id, 'shown');
    });

    test('uses the arrival window, not the sender’s clock', () {
      final detectedLongAgo = DateTime(2020);
      expect(
        pick([
          _received(
            'late-arrival',
            updatedAt: now.subtract(const Duration(minutes: 1)),
            detectedAt: detectedLongAgo,
          ),
        ])!
            .id,
        'late-arrival',
      );
      final futureArrival = now.add(const Duration(hours: 2));
      // A clock that stepped backwards must not hide a just-arrived alert.
      expect(pick([_received('clock-skew', updatedAt: futureArrival)])!.id, 'clock-skew');
    });

    test('includes the window boundary and excludes anything older', () {
      expect(
        pick([_received('edge', updatedAt: now.subtract(unseenAlertWindow))])!
            .id,
        'edge',
      );
      expect(
        pick([
          _received('stale', updatedAt: now.subtract(const Duration(minutes: 16))),
        ]),
        isNull,
      );
    });

    test('honours a shorter injected window', () {
      final incident = _received('ten', updatedAt: now.subtract(const Duration(minutes: 10)));
      expect(pick([incident], window: const Duration(minutes: 2)), isNull);
      expect(pick([incident], window: const Duration(minutes: 30))!.id, 'ten');
    });

    test('skips a disqualified newer alert and still returns an older one', () {
      final newerButOwn = _received('own', origin: 'self', updatedAt: now);
      final olderReceived = _received(
        'fallback',
        updatedAt: now.subtract(const Duration(minutes: 3)),
      );
      expect(pick([newerButOwn, olderReceived])!.id, 'fallback');
    });
  });

  group('alertReceivedArguments', () {
    test('carries every field the alert screen reads', () {
      final incident = _received(
        'a1',
        senderName: 'Ayan',
        latitude: 33.6844,
        longitude: 73.0479,
        locationText: 'Street 17, Gulberg',
      );
      final args = alertReceivedArguments(incident);
      expect(args['incidentId'], 'a1');
      expect(args['senderToken'], 'synthetic-sender-token');
      expect(args['senderName'], 'Ayan');
      expect(args['eventType'], 'Distress Sound');
      expect(args['riskScore'], '95');
      expect(args['riskLevel'], 'critical');
      expect(args['isSimulated'], 'false');
      expect(args['latitude'], '33.6844');
      expect(args['longitude'], '73.0479');
      expect(args['locationText'], 'Street 17, Gulberg');
      expect(
        args['detectedAt'],
        incident.detectionResult.detectedAt.toIso8601String(),
      );
    });

    test('omits senderName when absent or blank', () {
      expect(alertReceivedArguments(_received('a2')).containsKey('senderName'), isFalse);
      expect(
        alertReceivedArguments(_received('a3', senderName: '   '))
            .containsKey('senderName'),
        isFalse,
      );
    });

    test('omits location keys when there is no fix', () {
      final args = alertReceivedArguments(_received('a4'));
      expect(args.containsKey('latitude'), isFalse);
      expect(args.containsKey('longitude'), isFalse);
      expect(args.containsKey('locationText'), isFalse);
    });

    test('sends an empty senderToken instead of dropping the key', () {
      expect(
        alertReceivedArguments(_received('a5', senderToken: null))['senderToken'],
        '',
      );
    });
  });
}

Incident _received(
  String id, {
  DateTime? updatedAt,
  DateTime? detectedAt,
  RiskLevel riskLevel = RiskLevel.critical,
  IncidentStatus status = IncidentStatus.alertTriggered,
  String? contactResponseText,
  String origin = 'trusted_contact',
  String? senderToken = 'synthetic-sender-token',
  String? senderName,
  double? latitude,
  double? longitude,
  String? locationText,
}) {
  final arrival = updatedAt ?? DateTime(2026, 9, 21, 12);
  return Incident(
    id: id,
    detectionResult: DetectionResult(
      eventType: 'Distress Sound',
      confidence: .9,
      impactDetected: false,
      stillnessDetected: false,
      riskScore: riskLevel == RiskLevel.critical ? 95 : 60,
      riskLevel: riskLevel,
      detectedAt: detectedAt ?? arrival,
      latitude: latitude,
      longitude: longitude,
      locationText: locationText,
    ),
    status: status,
    createdAt: arrival,
    updatedAt: arrival,
    contactResponseText: contactResponseText,
    origin: origin,
    senderToken: senderToken,
    senderName: senderName,
  );
}
