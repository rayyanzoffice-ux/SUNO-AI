import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'alert_service.dart';

/// Firebase Cloud Messaging implementation of [AlertService].
///
/// The client cannot send FCM directly to another phone. It sends the
/// metadata-only alert payload to a trusted relay endpoint, and that server
/// function calls the FCM HTTP API with server credentials.
class FcmAlertService implements AlertService {
  FcmAlertService({
    required FirebaseMessaging messaging,
    String relayEndpoint = const String.fromEnvironment(
      'SUNO_ALERT_RELAY_URL',
    ),
  }) : _messaging = messaging,
       _relayEndpoint = relayEndpoint;

  final FirebaseMessaging _messaging;
  final String _relayEndpoint;
  String? _deviceToken;

  Future<String?> registerDevice() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _deviceToken = await _messaging.getToken();
    // ignore: avoid_print
    print('[SUNO FCM] This device token: $_deviceToken');
    return _deviceToken;
  }

  String? get deviceToken => _deviceToken;

  @override
  Future<void> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async {
    if (contactTokens.isEmpty) return;

    if (_relayEndpoint.trim().isEmpty) {
      // ignore: avoid_print
      print('[SUNO FCM] Relay not configured. Would notify '
          '${contactTokens.length} contact(s): ${jsonEncode(payload)}');
      return;
    }

    final uri = Uri.parse(_relayEndpoint);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'contactTokens': contactTokens,
        'payload': payload,
      }));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decodeStream(response);
        throw StateError(
          'Alert relay failed (${response.statusCode}): $body',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> cancelAlert(String incidentId) async {
    if (_relayEndpoint.trim().isEmpty) return;
    final uri = Uri.parse(_relayEndpoint);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'cancelIncidentId': incidentId,
      }));
      await request.close();
    } finally {
      client.close(force: true);
    }
  }
}

