import 'package:flutter/foundation.dart';

import '../backend/backend_exports.dart';
import '../models/alert_dispatch_result.dart';
import '../models/detection_result.dart';
import '../models/incident.dart';
import '../models/trusted_contact.dart';
import '../models/received_alert.dart';

enum DetectionScenario { low, medium, critical }

/// Frontend-facing coordinator for SUNO's framework-free backend services.
class SunoRuntimeService extends ChangeNotifier {
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
  AlertDispatchResult? lastDispatchResult;
  ReceivedAlert? receivedAlert;

  void acceptReceivedAlert(ReceivedAlert alert) {
    receivedAlert = alert;
    notifyListeners();
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
      lastDispatchResult =
          await notifyTrustedContactsForCurrentIncident();
    } else {
      lastDispatchResult = null;
    }
    notifyListeners();
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
    notifyListeners();
    return currentIncident;
  }

  Future<List<Incident>> getIncidentHistory() => _incidents.getAll();

  Future<void> removeIncident(String id) => _incidents.remove(id);

  Future<void> clearIncidentHistory() => _incidents.clear();

  /// Sends a response back to the original alert sender's device.
  Future<void> sendResponse({
    required String recipientToken,
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  }) async {
    final alertService = _alertService;
    if (alertService == null) {
      throw StateError('Alert service not available.');
    }
    await alertService.sendResponse(
      recipientToken: recipientToken,
      incidentId: incidentId,
      responderName: responderName,
      status: status,
      message: message,
    );
  }

  Future<List<TrustedContact>> getTrustedContacts() => _contacts.getAll();

  Future<TrustedContact> addTrustedContact(TrustedContact contact) =>
      _contacts.add(contact);

  Future<TrustedContact> updateTrustedContact(TrustedContact contact) =>
      _contacts.update(contact);

  Future<void> removeTrustedContact(String id) => _contacts.remove(id);

  /// Sends a silent test message to a single contact's FCM token and, if the
  /// relay reports success, marks the contact as verified locally.
  Future<bool> testContactNotification(TrustedContact contact) async {
    final alertService = _alertService;
    final token = contact.fcmToken;
    if (alertService == null || token == null || token.trim().isEmpty) {
      return false;
    }
    final ok = await alertService.sendTestMessage(token);
    if (ok) {
      final updated = TrustedContact(
        id: contact.id,
        name: contact.name,
        phone: contact.phone,
        relationship: contact.relationship,
        fcmToken: token,
        verifiedAt: DateTime.now(),
      );
      await _contacts.update(updated);
    }
    return ok;
  }

  Future<AlertDispatchResult> notifyTrustedContactsForCurrentIncident({
    String? onlyContactId,
  }) async {
    final alertService = _alertService;
    final incident = currentIncident;
    if (alertService == null || incident == null) {
      return const AlertDispatchResult(
        success: false,
        attemptedCount: 0,
        failedReason: 'Alert service not available',
      );
    }

    var contacts = await _contacts.getAll();
    if (onlyContactId != null) {
      contacts = contacts.where((c) => c.id == onlyContactId).toList();
    }
    final tokens = contacts
        .map((contact) => contact.fcmToken)
        .whereType<String>()
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return const AlertDispatchResult(
        success: false,
        attemptedCount: 0,
        failedReason: 'No contacts with an FCM token',
      );
    }

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
      if (alertService.deviceToken != null)
        'senderToken': alertService.deviceToken!,
    };

    try {
      await alertService.sendAlert(contactTokens: tokens, payload: payload);
      return AlertDispatchResult(
        success: true,
        attemptedCount: tokens.length,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[SUNO] Alert relay failed (non-fatal): $e');
      return AlertDispatchResult(
        success: false,
        attemptedCount: tokens.length,
        failedReason: e.toString(),
      );
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
    lastDispatchResult =
        await notifyTrustedContactsForCurrentIncident(onlyContactId: onlyContactId);
    return currentIncident;
  }

  /// Applies a response received from a trusted contact's device via FCM.
  Future<bool> applyContactResponse({
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  }) async {
    final existing = currentIncident;
    if (existing == null || existing.id != incidentId) {
      return false;
    }
    final now = DateTime.now();
    final updatedStatus = status == 'resolved'
        ? IncidentStatus.resolved
        : IncidentStatus.contactChecking;
    final updated = Incident(
      id: existing.id,
      detectionResult: existing.detectionResult,
      status: updatedStatus,
      createdAt: existing.createdAt,
      updatedAt: now,
      contactResponseText: '$responderName: $message',
    );
    currentIncident = await _incidents.update(updated);
    notifyListeners();
    return true;
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
      lastDispatchResult =
          await notifyTrustedContactsForCurrentIncident();
    }
    return currentIncident;
  }
}
