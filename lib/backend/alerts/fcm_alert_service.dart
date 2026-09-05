import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/config/app_config.dart';
import 'alert_service.dart';

/// Firebase Cloud Messaging implementation of [AlertService].
///
/// The client cannot send FCM directly to another phone. It sends the
/// metadata-only alert payload to a trusted relay endpoint, and that server
/// function calls the FCM HTTP API with server credentials.
class FcmAlertService implements AlertService {
  FcmAlertService({
    required FirebaseMessaging messaging,
    String? relayEndpoint,
  }) : _messaging = messaging,
       _relayEndpoint = relayEndpoint ?? AppConfig.alertRelayUrl;

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
  Future<bool> sendTestMessage(String token) async {
    if (_relayEndpoint.trim().isEmpty) {
      throw StateError('Alert relay URL is not configured.');
    }

    final uri = Uri.parse(_relayEndpoint);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'contactTokens': [token],
        'payload': {'type': 'test'},
        'test': true,
      }));
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Test message failed (${response.statusCode}): $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return false;
      return results.first['ok'] == true;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> sendResponse({
    required String recipientToken,
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  }) async {
    if (_relayEndpoint.trim().isEmpty) {
      throw StateError('Alert relay URL is not configured.');
    }
    if (recipientToken.trim().isEmpty) {
      throw StateError('Recipient token is missing.');
    }

    final uri = Uri.parse(_relayEndpoint);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'response': {
          'recipientToken': recipientToken,
          'incidentId': incidentId,
          'responderName': responderName,
          'status': status,
          'message': message,
        },
      }));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decodeStream(response);
        throw StateError('Response relay failed (${response.statusCode}): $body');
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

