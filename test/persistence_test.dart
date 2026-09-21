import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:suno_ai/backend/persistence/hive_incident_repository.dart';
import 'package:suno_ai/models/alert_dispatch_result.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/services/notification_inbox.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('suno-persistence-test-');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'Hive preserves metadata, upserts, sorts and keeps deleted IDs deleted',
    () async {
      Hive.init(directory.path);
      await Hive.openBox<Map>('incidents');
      const repository = HiveIncidentRepository();
      final older = _incident('older', DateTime(2026, 1));
      final newer = _incident('newer', DateTime(2026, 2));
      await repository.save(newer);
      await repository.save(older);
      await repository.save(older.copyWith(contactResponseText: 'Checking'));
      expect((await repository.getAll()).length, 2);
      expect((await repository.latest())!.id, 'newer');
      expect(() => (repository.getAll()), returnsNormally);
      final history = await repository.getAll();
      expect(() => history.clear(), throwsUnsupportedError);
      await Hive.close();
      await Hive.openBox<Map>('incidents');
      final restored = (await repository.latest())!;
      expect(restored.detectionResult.latitude, 33.6844);
      expect(restored.detectionResult.isSimulated, isTrue);
      expect(restored.safetyCheckDeadline, newer.safetyCheckDeadline);
      expect(restored.dispatchResult!.sentCount, 1);
      expect(restored.senderToken, 'synthetic-sender');
      await repository.remove('newer');
      await Hive.close();
      await Hive.openBox<Map>('incidents');
      expect(await repository.isDeleted('newer'), isTrue);
      expect((await repository.latest())!.id, 'older');
      expect(Hive.box<Map>('incidents').get('newer'), {'deleted': true});
      await expectLater(repository.save(newer), throwsStateError);
      await expectLater(repository.update(newer), throwsStateError);
      await repository.clear();
      expect(await repository.getAll(), isEmpty);
      expect(await repository.isDeleted('older'), isTrue);
    },
  );

  test(
    'inbox preserves concurrent messages and consumes only after acceptance',
    () async {
      final inbox = NotificationInbox(directory: directory);
      await Future.wait(
        List.generate(10, (i) => inbox.add({'incidentId': '$i'})),
      );
      await expectLater(
        inbox.drain((_) async {
          throw StateError('storage unavailable');
        }),
        throwsStateError,
      );
      expect(await directory.list().length, 10);
      final ids = <String>[];
      await inbox.drain((data) async {
        ids.add(data['incidentId']!);
      });
      expect(ids.toSet().length, 10);
      expect(await directory.list().length, 0);
      await inbox.drain((_) async {
        fail('Drained message replayed');
      });
    },
  );

  test('corrupt inbox messages do not block valid alerts or consume unfinished writes', () async {
    await File('${directory.path}/0.json').writeAsString('not json');
    await File('${directory.path}/1.json').writeAsString('{"riskScore": 50}');
    await File('${directory.path}/2.pending').writeAsString('{');
    final inbox = NotificationInbox(directory: directory);
    await inbox.add({'incidentId': 'valid'});
    final accepted = <String>[];
    await inbox.drain((data) async {
      accepted.add(data['incidentId']!);
    });
    expect(accepted, ['valid']);
    expect(
      (await directory.list().toList()).single.path,
      endsWith('2.pending'),
    );
  });
}

Incident _incident(String id, DateTime time) => Incident(
  id: id,
  detectionResult: DetectionResult(
    eventType: 'Synthetic demo',
    confidence: .9,
    impactDetected: false,
    stillnessDetected: false,
    riskScore: 50,
    riskLevel: RiskLevel.medium,
    detectedAt: time,
    latitude: 33.6844,
    longitude: 73.0479,
    isSimulated: true,
  ),
  status: IncidentStatus.contactNotified,
  createdAt: time,
  updatedAt: time,
  safetyCheckDeadline: time.add(const Duration(seconds: 10)),
  senderToken: 'synthetic-sender',
  dispatchResult: const AlertDispatchResult(
    success: false,
    attemptedCount: 2,
    sentCount: 1,
    failedReason: 'Partial acceptance',
  ),
);
