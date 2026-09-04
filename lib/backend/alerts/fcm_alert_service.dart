import 'dart:convert';
import 'dart:io';
import 'dart:async';

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
    String relayEndpoint = const String.fromEnvironment('SUNO_ALERT_RELAY_URL'),
    String relayAuthKey = const String.fromEnvironment('SUNO_RELAY_AUTH_KEY'),
  }) : _messaging = messaging,
       _relayEndpoint = relayEndpoint,
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

  String? get deviceToken => _deviceToken;

  @override
  Future<void> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async {
    if (contactTokens.isEmpty) return;

    if (_relayEndpoint.trim().isEmpty) {
      // ignore: avoid_print
      print(
        '[SUNO FCM] Relay not configured. Would notify '
        '${contactTokens.length} contact(s): ${jsonEncode(payload)}',
      );
      return;
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await utf8
            .decodeStream(response)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () =>
                  throw TimeoutException('Alert relay response timed out.'),
            );
        throw StateError('Alert relay failed (${response.statusCode}).');
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
