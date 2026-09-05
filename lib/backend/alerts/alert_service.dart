/// Abstract interface for delivering emergency alerts to trusted contacts.
abstract interface class AlertService {
  /// The token for this device, if push notifications are available.
  String? get deviceToken;

  /// Sends an emergency alert and returns the number of contacts that the
  /// relay reports as successfully accepted by FCM.
  Future<int> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  });

  /// Sends a silent, data-only test message to a single token.
  /// Returns true if the relay reports the message was accepted by FCM.
  Future<bool> sendTestMessage(String token);

  /// Sends a response back to the original sender's device.
  Future<void> sendResponse({
    required String recipientToken,
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  });

  Future<void> cancelAlert(String incidentId);
}
