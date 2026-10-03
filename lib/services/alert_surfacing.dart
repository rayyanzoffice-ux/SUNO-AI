import '../models/detection_result.dart';
import '../models/incident.dart';

/// How long after arrival an unanswered critical alert is still auto-opened.
const Duration unseenAlertWindow = Duration(minutes: 15);

/// Returns the newest received alert that should be put in front of the user,
/// or `null` if there is none.
///
/// A received incident qualifies when ALL of these hold:
/// - it came from a trusted contact (`isReceived`),
/// - its risk level is critical,
/// - it is still `alertTriggered` and the user has not responded to it
///   (`contactResponseText == null`),
/// - it is not in [alreadySurfaced] (already shown in this app session),
/// - it arrived within [window] of [now]. `updatedAt` is used (set by this
///   device when the alert was saved), NOT the sender's `detectedAt`, so a
///   wrong clock on the sender's phone cannot hide or resurrect alerts.
///
/// Pure function: no I/O, easy to unit-test.
Incident? pickUnseenReceivedAlert(
  Iterable<Incident> incidents, {
  required DateTime now,
  required Set<String> alreadySurfaced,
  Duration window = unseenAlertWindow,
}) {
  Incident? best;
  for (final incident in incidents) {
    if (!incident.isReceived) continue;
    if (incident.detectionResult.riskLevel != RiskLevel.critical) continue;
    if (incident.status != IncidentStatus.alertTriggered) continue;
    if (incident.contactResponseText != null) continue;
    if (alreadySurfaced.contains(incident.id)) continue;
    if (now.difference(incident.updatedAt) > window) continue;
    if (best == null || incident.updatedAt.isAfter(best.updatedAt)) {
      best = incident;
    }
  }
  return best;
}
