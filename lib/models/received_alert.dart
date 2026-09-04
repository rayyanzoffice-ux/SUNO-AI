class ReceivedAlert {
  const ReceivedAlert({
    required this.incidentId,
    required this.eventType,
    required this.riskScore,
    required this.riskLevel,
    required this.detectedAt,
    required this.location,
  });

  final String? incidentId;
  final String? eventType;
  final String? riskScore;
  final String? riskLevel;
  final String? detectedAt;
  final String? location;

  factory ReceivedAlert.fromData(Map<String, dynamic> data) {
    String? value(String key) {
      final raw = data[key];
      return raw is String && raw.trim().isNotEmpty ? raw : null;
    }

    return ReceivedAlert(
      incidentId: value('incidentId'),
      eventType: value('eventType'),
      riskScore: value('riskScore'),
      riskLevel: value('riskLevel'),
      detectedAt: value('detectedAt'),
      location: value('location') ?? value('locationText'),
    );
  }
}
