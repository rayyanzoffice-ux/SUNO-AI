import '../../models/detection_result.dart';
import '../../models/incident.dart';

/// Builds the route arguments that `AlertReceivedScreen` expects from a
/// persisted received [Incident].
///
/// Single source of truth so the notification router (main.dart) and the
/// History screen open the exact same screen with the exact same data.
Map<String, String> alertReceivedArguments(Incident incident) {
  final detection = incident.detectionResult;
  final name = incident.senderName?.trim();
  return <String, String>{
    'incidentId': incident.id,
    'senderToken': incident.senderToken ?? '',
    if (name != null && name.isNotEmpty) 'senderName': name,
    'eventType': detection.eventType,
    'riskScore': '${detection.riskScore}',
    'riskLevel': detection.riskLevel.wireValue,
    'detectedAt': detection.detectedAt.toIso8601String(),
    'isSimulated': '${detection.isSimulated}',
    if (detection.latitude != null) 'latitude': '${detection.latitude}',
    if (detection.longitude != null) 'longitude': '${detection.longitude}',
    if (detection.locationText != null) 'locationText': detection.locationText!,
  };
}
