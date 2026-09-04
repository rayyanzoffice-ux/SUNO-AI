import '../backend/backend_exports.dart';
import '../models/detection_result.dart';
import '../models/incident.dart';
import '../models/trusted_contact.dart';
import '../models/received_alert.dart';

enum DetectionScenario { low, medium, critical }

/// Frontend-facing coordinator for SUNO's framework-free backend services.
class SunoRuntimeService {
  SunoRuntimeService({
    DetectionEngine? detectionEngine,
    SafetyCheckEngine? safetyCheckEngine,
    IncidentRepository? incidentRepository,
    TrustedContactRepository? trustedContactRepository,
    AlertService? alertService,
  }) : _detectionEngine = detectionEngine ?? DetectionEngine.instance,
       _safetyCheckEngine = safetyCheckEngine ?? SafetyCheckEngine(),
       _incidents = incidentRepository ?? InMemoryIncidentRepository(),
       _contacts =
           trustedContactRepository ?? InMemoryTrustedContactRepository(),
       _alertService = alertService;

  static SunoRuntimeService instance = SunoRuntimeService();

  final DetectionEngine _detectionEngine;
  final SafetyCheckEngine _safetyCheckEngine;
  final IncidentRepository _incidents;
  final TrustedContactRepository _contacts;
  final AlertService? _alertService;

  Incident? currentIncident;
  ReceivedAlert? receivedAlert;

  void acceptReceivedAlert(ReceivedAlert alert) {
    receivedAlert = alert;
  }

  String? get deviceToken {
    final alertService = _alertService;
    return alertService is FcmAlertService ? alertService.deviceToken : null;
  }

  Future<String?> refreshDeviceToken() async {
    final alertService = _alertService;
    return alertService is FcmAlertService
        ? alertService.registerDevice()
        : null;
  }

  Future<DetectionResult> runDetection(DetectionScenario scenario) =>
      switch (scenario) {
        DetectionScenario.low => _detectionEngine.simulateLowRiskDetection(),
        DetectionScenario.medium => _detectionEngine.simulateMediumDetection(),
        DetectionScenario.critical =>
          _detectionEngine.simulateCriticalDetection(),
      };

  Future<Incident?> recordDetection(DetectionResult result) async {
    if (result.riskLevel == RiskLevel.low) return null;
    final now = DateTime.now();
    final status = result.riskLevel == RiskLevel.medium
        ? IncidentStatus.safetyCheck
        : IncidentStatus.alertTriggered;
    final incident = Incident(
      id: 'SUNO-${now.microsecondsSinceEpoch}',
      detectionResult: result,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    currentIncident = await _incidents.save(incident);
    if (status == IncidentStatus.alertTriggered) {
      await notifyTrustedContactsForCurrentIncident();
    }
    return currentIncident;
  }

  Future<Incident?> updateStatus(
    IncidentStatus status, [
    String? response,
  ]) async {
    final existing = currentIncident;
    if (existing == null) return null;
    final now = DateTime.now();
    final updated = Incident(
      id: existing.id,
      detectionResult: existing.detectionResult,
      status: status,
      createdAt: existing.createdAt,
      updatedAt: now,
      contactResponseText: response ?? existing.contactResponseText,
    );
    currentIncident = await _incidents.update(updated);
    return currentIncident;
  }

  Future<List<Incident>> getIncidentHistory() => _incidents.getAll();

  Future<List<TrustedContact>> getTrustedContacts() => _contacts.getAll();

  Future<TrustedContact> addTrustedContact(TrustedContact contact) =>
      _contacts.add(contact);

  Future<void> notifyTrustedContactsForCurrentIncident({
    String? onlyContactId,
  }) async {
    final alertService = _alertService;
    final incident = currentIncident;
    if (alertService == null || incident == null) return;

    var contacts = await _contacts.getAll();
    if (onlyContactId != null) {
      contacts = contacts.where((c) => c.id == onlyContactId).toList();
    }
    final tokens = contacts
        .map((contact) => contact.fcmToken)
        .whereType<String>()
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return;

    final detection = incident.detectionResult;
    final payload = <String, String>{
      'incidentId': incident.id,
      'eventType': detection.eventType,
      'riskScore': detection.riskScore.toString(),
      'riskLevel': detection.riskLevel.wireValue,
      'detectedAt': detection.detectedAt.toIso8601String(),
      if (detection.latitude != null) 'latitude': detection.latitude.toString(),
      if (detection.longitude != null)
        'longitude': detection.longitude.toString(),
      if (detection.locationText != null)
        'locationText': detection.locationText!,
    };

    try {
      await alertService.sendAlert(contactTokens: tokens, payload: payload);
    } catch (_) {
      // ignore: avoid_print
      print('[SUNO] Alert relay delivery failed (non-fatal).');
    }
  }

  Future<Incident?> triggerManualAlert({String? onlyContactId}) async {
    final location = await LocationService().currentLocation();
    final now = DateTime.now();
    final result = DetectionResult(
      eventType: 'Manual Silent Alert',
      confidence: 1.0,
      impactDetected: false,
      stillnessDetected: false,
      riskScore: 100,
      riskLevel: RiskLevel.critical,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationText: location != null
          ? '${location.latitude.toStringAsFixed(4)}, '
                '${location.longitude.toStringAsFixed(4)}'
          : null,
      detectedAt: now,
    );

    final incident = Incident(
      id: 'SUNO-${now.microsecondsSinceEpoch}',
      detectionResult: result,
      status: IncidentStatus.alertTriggered,
      createdAt: now,
      updatedAt: now,
    );
    currentIncident = await _incidents.save(incident);
    await notifyTrustedContactsForCurrentIncident(onlyContactId: onlyContactId);
    return currentIncident;
  }

  Future<SafetyCheckResult> startSafetyCheck() {
    final incident = currentIncident;
    if (incident == null) {
      throw StateError('A saved incident is required for a safety check.');
    }
    return _safetyCheckEngine.startCountdown(incident.detectionResult);
  }

  void confirmSafe() => _safetyCheckEngine.confirmSafe();

  void escalateSafetyCheck() => _safetyCheckEngine.escalateNow();

  void cancelSafetyCheck() => _safetyCheckEngine.dispose();

  Future<Incident?> applySafetyCheckResult(SafetyCheckResult result) async {
    final existing = currentIncident;
    if (existing == null || result.outcome == SafetyCheckOutcome.cancelled) {
      return existing;
    }
    final now = DateTime.now();
    final updated = Incident(
      id: existing.id,
      detectionResult: result.detectionResult,
      status: result.outcome == SafetyCheckOutcome.userConfirmedSafe
          ? IncidentStatus.cancelled
          : IncidentStatus.alertTriggered,
      createdAt: existing.createdAt,
      updatedAt: now,
      contactResponseText:
          result.outcome == SafetyCheckOutcome.userConfirmedSafe
          ? 'User confirmed safe'
          : 'No response received',
    );
    currentIncident = await _incidents.update(updated);
    if (updated.status == IncidentStatus.alertTriggered) {
      await notifyTrustedContactsForCurrentIncident();
    }
    return currentIncident;
  }
}
