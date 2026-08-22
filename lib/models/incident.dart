import 'detection_result.dart';

enum IncidentStatus {
  monitoring,
  safetyCheck,
  alertTriggered,
  contactNotified,
  contactChecking,
  resolved,
  cancelled,
}

extension IncidentStatusContract on IncidentStatus {
  String get wireValue => switch (this) {
    IncidentStatus.monitoring => 'detected',
    IncidentStatus.safetyCheck => 'safety_check',
    IncidentStatus.alertTriggered => 'alert_triggered',
    IncidentStatus.contactNotified => 'contact_notified',
    IncidentStatus.contactChecking => 'contact_checking',
    IncidentStatus.resolved => 'resolved',
    IncidentStatus.cancelled => 'cancelled_by_user',
  };
}

class Incident {
  Incident({
    required this.id,
    required this.detectionResult,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.contactResponseText,
  });

  final String id;
  final DetectionResult detectionResult;
  IncidentStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  String? contactResponseText;
}
