import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/alerts/sms_fallback_service.dart';
import 'package:suno_ai/models/trusted_contact.dart';

void main() {
  TrustedContact contact(String phone, {String id = 'c'}) => TrustedContact(
    id: id,
    name: 'Test contact',
    phone: phone,
    relationship: 'Friend',
  );

  test('stored formatting is cleaned into a dialable number', () async {
    final send = _FakeSend();
    final result = await SmsFallbackService(send: send.call).sendAlert(
      contacts: [
        contact('(300) 123-4567'),
        contact('+92 300-123 4567'),
        contact('  03001234567  '),
        contact('   '),
        contact('not a number'),
      ],
      payload: const {'eventType': 'Distress Sound'},
    );
    expect(
      send.numbers,
      ['3001234567', '+923001234567', '03001234567'],
      reason: 'only a leading + survives; every other separator is stripped',
    );
    expect(result.attempted, 3);
    expect(result.sent, 3);
  });

  test('contacts without a number are not attempted', () async {
    final send = _FakeSend();
    final result = await SmsFallbackService(send: send.call).sendAlert(
      contacts: [contact(''), contact('  ')],
      payload: const {'eventType': 'Distress Sound'},
    );
    expect(result.attempted, 0);
    expect(result.sent, 0);
    expect(send.numbers, isEmpty);
  });

  test('the same number is only dialled once', () async {
    final send = _FakeSend();
    final result = await SmsFallbackService(
      send: send.call,
    ).sendAlert(
      contacts: [
        contact('+92 300-123-4567', id: 'a'),
        contact('+923001234567', id: 'b'),
      ],
      payload: const {'eventType': 'Distress Sound'},
    );
    expect(send.numbers, ['+923001234567']);
    expect(result.attempted, 1);
    expect(result.sent, 1);
  });

  test('only sends the SIM accepted are counted', () async {
    final send = _FakeSend()..failsFor = {'3001234567'};
    final result = await SmsFallbackService(send: send.call).sendAlert(
      contacts: [contact('(300) 123-4567', id: 'a'), contact('777', id: 'b')],
      payload: const {'eventType': 'Distress Sound'},
    );
    expect(result.attempted, 2);
    expect(result.sent, 1);
  });

  test('every contact gets the same message', () async {
    final send = _FakeSend();
    await SmsFallbackService(send: send.call).sendAlert(
      contacts: [contact('111', id: 'a'), contact('222', id: 'b')],
      payload: const {'eventType': 'Distress Sound', 'riskScore': '95'},
    );
    expect(send.messages.length, 2);
    expect(send.messages.values.toSet().length, 1);
  });

  test('the message names the sender, the risk and a maps link', () async {
    final send = _FakeSend();
    await SmsFallbackService(send: send.call).sendAlert(
      contacts: [contact('111')],
      payload: const {
        'senderName': 'Ayaan',
        'eventType': 'Distress Sound',
        'riskScore': '95',
        'latitude': '33.6844',
        'longitude': '73.0479',
      },
    );
    expect(
      send.messages['111'],
      'SUNO EMERGENCY: Ayaan - Distress Sound (risk 95%). '
      'Location: https://maps.google.com/?q=33.6844,73.0479. '
      'Sent by SMS - SUNO could not reach the push alert.',
    );
  });

  test('a cached fix admits its age instead of posing as live', () async {
    final send = _FakeSend();
    await SmsFallbackService(send: send.call).sendAlert(
      contacts: [contact('111')],
      payload: const {
        'eventType': 'Impact / Breaking Sound',
        'latitude': '33.6844',
        'longitude': '73.0479',
        'locationIsCached': 'true',
        'locationAgeMinutes': '12',
      },
    );
    expect(send.messages['111'], contains('(last known fix, 12m old)'));
  });

  test('no coordinates are reported as unavailable', () async {
    final send = _FakeSend();
    await SmsFallbackService(send: send.call).sendAlert(
      contacts: [contact('111')],
      payload: const {'eventType': 'Emergency Alarm'},
    );
    expect(send.messages['111'], contains('Location unavailable.'));
    expect(send.messages['111'], isNot(contains('maps.google.com')));
  });
}

/// Stands in for the native channel: records each dialled number and the text
/// that went with it, and decides per number whether the OS accepted the send.
class _FakeSend {
  final messages = <String, String>{};
  Set<String> failsFor = {};

  List<String> get numbers => messages.keys.toList();

  Future<bool> call({
    required String phoneNumber,
    required String message,
  }) async {
    messages[phoneNumber] = message;
    return !failsFor.contains(phoneNumber);
  }
}
