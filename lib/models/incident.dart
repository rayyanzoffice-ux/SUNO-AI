import 'alert_dispatch_result.dart';
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
  const Incident({
    required this.id,
    required this.detectionResult,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.contactResponseText,
    this.origin = 'self',
    this.safetyCheckDeadline,
    this.dispatchResult,
    this.senderToken,
  });

  final String id;
  final DetectionResult detectionResult;
  final IncidentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? contactResponseText;
  final String origin;
  final DateTime? safetyCheckDeadline;
  final AlertDispatchResult? dispatchResult;
  final String? senderToken;

  bool get isReceived => origin != 'self';

  Incident copyWith({
    DetectionResult? detectionResult,
    IncidentStatus? status,
    DateTime? updatedAt,
    String? contactResponseText,
    AlertDispatchResult? dispatchResult,
  }) => Incident(
    id: id,
    detectionResult: detectionResult ?? this.detectionResult,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    contactResponseText: contactResponseText ?? this.contactResponseText,
    origin: origin,
    safetyCheckDeadline: safetyCheckDeadline,
    dispatchResult: dispatchResult ?? this.dispatchResult,
    senderToken: senderToken,
  );
}
