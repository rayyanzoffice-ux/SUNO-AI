import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/config/app_config.dart';
import 'alert_service.dart';

class FcmAlertService implements AlertService {
  FcmAlertService({
    required this._messaging,
    String? relayEndpoint,
    this._relayAuthKey = const String.fromEnvironment('SUNO_RELAY_AUTH_KEY'),
  }) : _relayEndpoint = relayEndpoint ?? AppConfig.alertRelayUrl;

  final FirebaseMessaging _messaging;
  final String _relayEndpoint;
  final String _relayAuthKey;
  String? _deviceToken;
  StreamSubscription<String>? _tokenRefreshSubscription;
  Future<String?>? _registration;

  Future<String?> registerDevice() => _registration ??= _registerDevice()
      .whenComplete(() => _registration = null);

  Future<String?> _registerDevice() async {
    final settings = await _messaging
        .requestPermission(alert: true, badge: true, sound: true)
        .timeout(const Duration(seconds: 30));
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      throw StateError(
        'Enable SUNO notifications in Android Settings, then retry.',
      );
    }
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen(
      (token) => _deviceToken = token,
      onError: (Object _) {
        _deviceToken = null;
      },
    );
    _deviceToken = await _messaging.getToken().timeout(
      const Duration(seconds: 12),
    );
    if (_deviceToken == null) {
      throw StateError('Push token unavailable. Check connectivity and retry.');
    }
    return _deviceToken;
  }

  @override
  String? get deviceToken => _deviceToken;

  @override
  Future<Set<String>> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async {
    final tokens = contactTokens.map((token) => token.trim()).toSet().toList();
    if (tokens.isEmpty) return <String>{};
    if (tokens.any((token) => token.length < 21 || token.length > 4096)) {
      throw StateError(
        'A contact token is invalid. Update it in Trusted Contacts.',
      );
    }
    final batches = <List<String>>[];
    var batch = <String>[];
    for (final token in tokens) {
      final candidate = [...batch, token];
      if (candidate.length > 10 || _bodySize(candidate, payload) > 16384) {
        if (batch.isEmpty) throw StateError('Alert payload is too large.');
        batches.add(batch);
        batch = <String>[];
      }
      batch.add(token);
      if (_bodySize(batch, payload) > 16384) {
        throw StateError('Alert payload is too large.');
      }
    }
    if (batch.isNotEmpty) batches.add(batch);
    final accepted = <String>{};
    Object? failure;
    for (final recipients in batches) {
      try {
        final result = await _post({
          'contactTokens': recipients,
          'payload': payload,
        });
        accepted.addAll(_acceptedTokens(result, recipients));
      } catch (error) {
        failure = error;
      }
    }
    // An unsuccessful later batch must not erase already accepted deliveries.
    if (accepted.isEmpty && failure != null) {
      throw StateError(
        'Alert relay unavailable. Check connectivity and configuration.',
      );
    }
    return accepted;
  }

  /// Matches the relay's per-delivery `results` array back to the token list
  /// sent in this batch. `deliveries` is built from the same deduplicated
  /// token list, in order, so the arrays line up.
  Set<String> _acceptedTokens(
    Map<String, dynamic> result,
    List<String> sentTokens,
  ) {
    final sent = result['sent'];
    final attempted = result['attempted'];
    final results = result['results'];
    if (sent is! int ||
        attempted is! int ||
        attempted != sentTokens.length ||
        sent < 0 ||
        sent > attempted ||
        results is! List ||
        results.length != sentTokens.length) {
      throw StateError('Alert relay returned an invalid acceptance count.');
    }
    final accepted = <String>{};
    for (var i = 0; i < sentTokens.length; i++) {
      final entry = results[i];
      if (entry is Map && entry['ok'] == true) accepted.add(sentTokens[i]);
    }
    if (accepted.length != sent) {
      throw StateError('Alert relay returned an invalid acceptance count.');
    }
    return accepted;
  }

  int _bodySize(List<String> tokens, Map<String, String> payload) => utf8
      .encode(jsonEncode({'contactTokens': tokens, 'payload': payload}))
      .length;

  int _acceptedCount(Map<String, dynamic> result, int expected) {
    final sent = result['sent'];
    final attempted = result['attempted'];
    if (sent is! int ||
        attempted is! int ||
        attempted != expected ||
        sent < 0 ||
        sent > attempted) {
      throw StateError('Alert relay returned an invalid acceptance count.');
    }
    return sent;
  }

  @override
  Future<bool> sendTestMessage(String token) async {
    final result = await _post({
      'contactTokens': [token.trim()],
      'payload': {'type': 'test'},
      'test': true,
    });
    return _acceptedCount(result, 1) == 1;
  }

  @override
  Future<void> sendResponse({
    required String recipientToken,
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
    String? recipientLang,
  }) async {
    if (recipientToken.trim().isEmpty) {
      throw StateError('Sender token is missing.');
    }
    final result = await _post({
      'response': {
        'recipientToken': recipientToken.trim(),
        'incidentId': incidentId,
        'responderName': responderName,
        'status': status,
        'message': message,
        'lang': ?recipientLang,
      },
    });
    if (_acceptedCount(result, 1) != 1) {
      throw StateError('FCM did not accept this response. Please retry.');
    }
  }

  @override
  Future<void> cancelAlert(String incidentId) async {
    await _post({'cancelIncidentId': incidentId});
  }

  Future<Map<String, dynamic>> _post(Map<String, Object> body) async {
    if (_relayEndpoint.trim().isEmpty || _relayAuthKey.trim().isEmpty) {
      throw StateError('Alert relay configuration is missing.');
    }
    final bytes = utf8.encode(jsonEncode(body));
    if (bytes.length > 16384) throw StateError('Alert payload is too large.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final request = await client.postUrl(Uri.parse(_relayEndpoint));
        request.headers.contentType = ContentType.json;
        request.headers.set('X-SUNO-Relay-Key', _relayAuthKey.trim());
        request.add(bytes);
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError('Alert relay failed (${response.statusCode}).');
        }
        final data = <int>[];
        await for (final chunk in response) {
          if (data.length + chunk.length > 65536) {
            throw StateError('Invalid relay response.');
          }
          data.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is! Map<String, dynamic>) {
          throw StateError('Invalid relay response.');
        }
        return decoded;
      })().timeout(const Duration(seconds: 20));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}
