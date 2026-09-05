import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/config/app_config.dart';
import 'alert_service.dart';

class FcmAlertService implements AlertService {
  FcmAlertService({
    required FirebaseMessaging messaging,
    String? relayEndpoint,
    String relayAuthKey = const String.fromEnvironment('SUNO_RELAY_AUTH_KEY'),
  }) : _messaging = messaging,
       _relayEndpoint = relayEndpoint ?? AppConfig.alertRelayUrl,
       _relayAuthKey = relayAuthKey;

  final FirebaseMessaging _messaging;
  final String _relayEndpoint;
  final String _relayAuthKey;
  String? _deviceToken;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Future<String?> registerDevice() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    _deviceToken = await _messaging.getToken();
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
      _deviceToken = token;
      // ignore: avoid_print
      print('[SUNO FCM] Device token refreshed: ${_redactToken(token)}');
    });
    // ignore: avoid_print
    print('[SUNO FCM] This device token: ${_redactToken(_deviceToken)}');
    return _deviceToken;
  }

  @override
  String? get deviceToken => _deviceToken;

  @override
  Future<int> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async {
    if (contactTokens.isEmpty) return 0;

    if (_relayEndpoint.trim().isEmpty) {
      throw StateError('Alert relay URL is not configured.');
    }

    final uri = Uri.parse(_relayEndpoint);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      _setRelayHeaders(request);
      request.write(
        jsonEncode({'contactTokens': contactTokens, 'payload': payload}),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException('Alert relay response timed out.'),
      );
      final body = await utf8.decodeStream(response).timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException('Alert relay response timed out.'),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Alert relay failed (${response.statusCode}): $body');
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final sent = decoded['sent'];
      final attempted = decoded['attempted'];
      if (sent is! int) {
        throw StateError('Alert relay returned an invalid delivery result.');
      }
      if (attempted is int && attempted != contactTokens.length) {
        throw StateError(
          'Alert relay attempted $attempted/${contactTokens.length} contacts.',
        );
      }
      if (sent == 0) {
        throw StateError(
          'Alert relay delivered to 0/${contactTokens.length} contacts.',
        );
      }
      return sent;
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      _setRelayHeaders(request);
      request.write(jsonEncode({
        'contactTokens': [token],
        'payload': {'type': 'test'},
        'test': true,
      }));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException('Test message response timed out.'),
      );
      final body = await utf8.decodeStream(response).timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException('Test message response timed out.'),
      );
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      _setRelayHeaders(request);
      request.write(jsonEncode({
        'response': {
          'recipientToken': recipientToken,
          'incidentId': incidentId,
          'responderName': responderName,
          'status': status,
          'message': message,
        },
      }));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException('Response relay response timed out.'),
      );
      final body = await utf8.decodeStream(response).timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException('Response relay response timed out.'),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Response relay failed (${response.statusCode}): $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['ok'] != true || decoded['sent'] != 1) {
        throw StateError('Response relay did not deliver the contact response.');
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> cancelAlert(String incidentId) async {
    if (_relayEndpoint.trim().isEmpty) return;
    final uri = Uri.parse(_relayEndpoint);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      _setRelayHeaders(request);
      request.write(jsonEncode({'cancelIncidentId': incidentId}));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException('Alert cancellation timed out.'),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Alert cancellation failed (${response.statusCode}).');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  void _setRelayHeaders(HttpClientRequest request) {
    if (_relayAuthKey.trim().isNotEmpty) {
      request.headers.set('X-SUNO-Relay-Key', _relayAuthKey.trim());
    }
  }

  static String _redactToken(String? token) {
    if (token == null || token.isEmpty) return '<unavailable>';
    if (token.length <= 10) return 'REDACTED';
    return '${token.substring(0, 7)}...REDACTED...${token.substring(token.length - 4)}';
  }
}
