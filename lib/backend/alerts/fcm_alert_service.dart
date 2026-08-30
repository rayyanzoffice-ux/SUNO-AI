import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'alert_service.dart';

/// Firebase Cloud Messaging implementation of [AlertService].
///
/// This device registers for push notifications and stores its FCM token.
/// Actual delivery to trusted contacts requires a server-side component
/// (Supabase Edge Function or Firebase Cloud Function) that accepts the
/// payload and sends FCM messages to the contact tokens.
/// See SETUP_INSTRUCTIONS.md for the backend wiring.
class FcmAlertService implements AlertService {
  FcmAlertService({required FirebaseMessaging messaging})
    : _messaging = messaging;

  final FirebaseMessaging _messaging;
  String? _deviceToken;

  Future<String?> registerDevice() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _deviceToken = await _messaging.getToken();
    return _deviceToken;
  }

  String? get deviceToken => _deviceToken;

  @override
  Future<void> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  }) async {
    // In demo mode: print payload. Replace with HTTP POST to your
    // Supabase Edge Function or Firebase Cloud Functions endpoint.
    // ignore: avoid_print
    print('[SUNO FCM] Would notify ${contactTokens.length} contact(s): '
          '${jsonEncode(payload)}');
  }

  @override
  Future<void> cancelAlert(String incidentId) async {
    // ignore: avoid_print
    print('[SUNO FCM] Cancel alert for incident $incidentId');
  }
}
