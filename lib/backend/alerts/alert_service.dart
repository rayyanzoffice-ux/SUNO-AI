/// Abstract interface for delivering emergency alerts to trusted contacts.
abstract interface class AlertService {
  Future<void> sendAlert({
    required List<String> contactTokens,
    required Map<String, String> payload,
  });

  Future<void> cancelAlert(String incidentId);
}
