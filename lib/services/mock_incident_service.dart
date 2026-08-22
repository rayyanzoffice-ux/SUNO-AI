import '../models/detection_result.dart';
import '../models/incident.dart';
import '../models/trusted_contact.dart';

class MockIncidentService {
  MockIncidentService._();
  static final instance = MockIncidentService._();

  static const locationText = 'Lahore, Pakistan';
  static const contact = TrustedContact(
    id: 'contact-1',
    name: 'Rayyan Brother',
    phone: '+92 300 0000000',
    relationship: 'Brother',
  );

  Incident? currentIncident;

  // TODO: Replace in-memory incident state with the backend incident repository.

  Incident createIncident(DetectionResult detection) {
    final now = DateTime.now();
    return currentIncident = Incident(
      id: 'SUNO-${now.millisecondsSinceEpoch}',
      detectionResult: detection,
      status: IncidentStatus.alertTriggered,
      createdAt: now,
      updatedAt: now,
    );
  }

  void updateStatus(IncidentStatus status, [String? response]) {
    currentIncident?.status = status;
    currentIncident?.contactResponseText = response;
    currentIncident?.updatedAt = DateTime.now();
  }

  String locationFor(DetectionResult result) =>
      result.locationText ?? locationText;
}
