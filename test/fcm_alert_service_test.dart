import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/alerts/fcm_alert_service.dart';

void main() {
  late HttpServer server;
  late FcmAlertService service;
  late List<Map<String, dynamic>> bodies;
  late List<int> sizes;
  late Future<void> Function(HttpRequest, Map<String, dynamic>) respond;
  setUp(() async {
    bodies = [];
    sizes = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request, body) async {
      final count = (body['contactTokens'] as List?)?.length ?? 1;
      request.response.write(jsonEncode({'sent': count, 'attempted': count}));
    };
    server.listen((request) async {
      final data = await request.fold<List<int>>(
        [],
        (data, chunk) => data..addAll(chunk),
      );
      sizes.add(data.length);
      final body = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      bodies.add(body);
      expect(request.headers.value('x-suno-relay-key'), 'synthetic-key');
      await respond(request, body);
      await request.response.close();
    });
    service = FcmAlertService(
      messaging: _Messaging(),
      relayEndpoint: 'http://127.0.0.1:${server.port}',
      relayAuthKey: 'synthetic-key',
    );
  });
  tearDown(() async {
    await service.dispose();
    await server.close(force: true);
  });

  test('normalizes and deduplicates tokens in batches of ten', () async {
    final tokens = List.generate(12, (i) => 'synthetic-recipient-token-$i');
    expect(
      await service.sendAlert(
        contactTokens: [...tokens, ' ${tokens.first} '],
        payload: {},
      ),
      12,
    );
    expect(bodies.map((b) => (b['contactTokens'] as List).length), [10, 2]);
    expect(bodies.first['contactTokens'], tokens.take(10).toList());
  });

  test('large tokens are batched by encoded request bytes', () async {
    final tokens = List.generate(8, (i) => '$i${'a' * 3999}');
    expect(
      await service.sendAlert(
        contactTokens: tokens,
        payload: {'eventType': 'test'},
      ),
      8,
    );
    expect(bodies.length, 2);
    expect(sizes.every((size) => size <= 16384), isTrue);
  });

  test(
    'acceptance from an earlier batch survives a later HTTP failure',
    () async {
      respond = (request, body) async {
        if (bodies.length == 1) {
          request.response.write(jsonEncode({'sent': 9, 'attempted': 10}));
        } else {
          request.response.statusCode = 503;
          request.response.write('upstream-private-details');
        }
      };
      expect(
        await service.sendAlert(
          contactTokens: List.generate(
            11,
            (i) => 'synthetic-recipient-token-$i',
          ),
          payload: {},
        ),
        9,
      );
    },
  );

  test('invalid acceptance accounting is rejected', () async {
    for (final result in [
      {'sent': 2, 'attempted': 1},
      {'sent': -1, 'attempted': 1},
      {'sent': '1', 'attempted': 1},
      {'sent': 1, 'attempted': 2},
    ]) {
      respond = (request, body) async =>
          request.response.write(jsonEncode(result));
      await expectLater(
        service.sendAlert(
          contactTokens: ['synthetic-recipient-token'],
          payload: {},
        ),
        throwsStateError,
      );
    }
  });

  test(
    'silent tests include nested payload and responses retain incident ID',
    () async {
      expect(
        await service.sendTestMessage(' synthetic-recipient-token '),
        isTrue,
      );
      expect(bodies.single, {
        'contactTokens': ['synthetic-recipient-token'],
        'payload': {'type': 'test'},
        'test': true,
      });
      await service.sendResponse(
        recipientToken: 'synthetic-recipient-token',
        incidentId: 'older-incident',
        responderName: 'Test contact',
        status: 'resolved',
        message: 'Safe',
      );
      expect(bodies.last['response']['incidentId'], 'older-incident');
      respond = (request, body) async =>
          request.response.write('{"sent":0,"attempted":1}');
      await expectLater(
        service.sendResponse(
          recipientToken: 'synthetic-recipient-token',
          incidentId: 'older-incident',
          responderName: 'Test contact',
          status: 'resolved',
          message: 'Safe',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'missing configuration and invalid tokens never reach the server',
    () async {
      final unconfigured = FcmAlertService(
        messaging: _Messaging(),
        relayEndpoint: 'http://127.0.0.1:${server.port}',
        relayAuthKey: '',
      );
      await expectLater(
        unconfigured.sendTestMessage('synthetic-recipient-token'),
        throwsStateError,
      );
      await expectLater(
        service.sendAlert(contactTokens: ['short'], payload: {}),
        throwsStateError,
      );
      await expectLater(
        service.sendAlert(
          contactTokens: ['synthetic-recipient-token'],
          payload: {'huge': 'x' * 17000},
        ),
        throwsStateError,
      );
      expect(bodies, isEmpty);
      await unconfigured.dispose();
    },
  );

  test('oversized and non-object relay responses are rejected', () async {
    respond = (request, body) async => request.response.write('x' * 65537);
    await expectLater(
      service.sendTestMessage('synthetic-recipient-token'),
      throwsStateError,
    );
    respond = (request, body) async => request.response.write('[]');
    await expectLater(
      service.sendTestMessage('synthetic-recipient-token'),
      throwsStateError,
    );
  });
}

class _Messaging extends Fake implements FirebaseMessaging {}
