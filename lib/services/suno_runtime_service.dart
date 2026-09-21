import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../backend/backend_exports.dart';
import '../models/alert_dispatch_result.dart';
import '../models/detection_result.dart';
import '../models/incident.dart';
import '../models/received_alert.dart';
import '../models/trusted_contact.dart';

enum DetectionScenario { low, medium, critical }

class SunoRuntimeService extends ChangeNotifier {
  SunoRuntimeService({
    DetectionEngine? detectionEngine,
    SafetyCheckEngine? safetyCheckEngine,
    IncidentRepository? incidentRepository,
    TrustedContactRepository? trustedContactRepository,
    this._alertService,
    LocationService? locationService,
  }) : _detectionEngine = detectionEngine ?? DetectionEngine.instance,
       _safetyCheckEngine = safetyCheckEngine ?? SafetyCheckEngine(),
       _incidents = incidentRepository ?? InMemoryIncidentRepository(),
       _contacts =
           trustedContactRepository ?? InMemoryTrustedContactRepository(),
       locationService = locationService ?? LocationService();

  static SunoRuntimeService instance = SunoRuntimeService();
  final DetectionEngine _detectionEngine;
  final SafetyCheckEngine _safetyCheckEngine;
  final IncidentRepository _incidents;
  final TrustedContactRepository _contacts;
  final AlertService? _alertService;
  final LocationService locationService;
  final Map<String, Incident> _knownIncidents = {};
  final Map<String, Future<AlertDispatchResult>> _dispatches = {};
  final Set<String> _deleted = {};
  Future<void> _mutations = Future.value();
  Future<Incident?>? _recording;
  Future<LocationSnapshot?>? _locationRequest;
  Future<void>? _safetyTask;
  String? _safetyIncidentId;
  bool _safetySaveFailed = false;
  bool _disposed = false;

  Incident? currentIncident;
  ReceivedAlert? receivedAlert;
  LocationSnapshot? location;
  String? operationError;

  AlertDispatchResult? get lastDispatchResult =>
      currentIncident?.dispatchResult;
  bool get locating => _locationRequest != null;
  bool get hasPendingSafetyCheck => _safetyIncidentId != null;
  bool get safetyCheckNeedsRetry => _safetySaveFailed;
  bool get hasPendingDispatch => _dispatches.isNotEmpty;

  void reportError(String message) {
    operationError = message;
    _changed();
  }

  Future<void> get safetyCheckCompleted => _safetyTask ?? Future.value();
  bool isDispatching(String id) => _dispatches.containsKey(id);
  Incident? incidentById(String id) => _knownIncidents[id];
  String? get deviceToken => _alertService?.deviceToken;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _mutations.then((_) => operation());
    _mutations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> restoreLatestIncident() async {
    final history = await _incidents.getAll();
    _knownIncidents.addEntries(
      history.map((incident) => MapEntry(incident.id, incident)),
    );
    currentIncident = history
        .where((incident) => !incident.isReceived)
        .firstOrNull;
    final pending = history
        .where(
          (incident) =>
              !incident.isReceived &&
              incident.status == IncidentStatus.safetyCheck,
        )
        .firstOrNull;
    if (pending != null) {
      currentIncident = pending;
      _beginSafetyCheck(pending);
    }
    _changed();
  }

  Future<LocationSnapshot?> refreshLocation({bool requestPermission = true}) {
    final pending = _locationRequest;
    if (pending != null) return pending;
    final request = locationService
        .currentLocation(requestPermission: requestPermission)
        .then((value) {
          location = value;
          return value;
        })
        .whenComplete(() {
          _locationRequest = null;
          _changed();
        });
    _locationRequest = request;
    _changed();
    return request;
  }

  Future<String?> refreshDeviceToken() async {
    final service = _alertService;
    return service is FcmAlertService
        ? service.registerDevice()
        : service?.deviceToken;
  }

  Future<DetectionResult> runDetection(DetectionScenario scenario) async {
    final position = await refreshLocation();
    final result = await switch (scenario) {
      DetectionScenario.low => _detectionEngine.simulateLowRiskDetection(),
      DetectionScenario.medium => _detectionEngine.simulateMediumDetection(),
      DetectionScenario.critical =>
        _detectionEngine.simulateCriticalDetection(),
    };
    return result.copyWith(
      latitude: position?.latitude,
      longitude: position?.longitude,
      locationText: position?.description,
      detectedAt: DateTime.now(),
    );
  }

  Future<Incident?> recordDetection(DetectionResult result) {
    if (result.riskLevel == RiskLevel.low) return Future.value(null);
    if (hasPendingSafetyCheck || hasPendingDispatch) {
      return Future.value(currentIncident);
    }
    return _recording ??= _record(result).whenComplete(() => _recording = null);
  }

  Future<Incident> _record(
    DetectionResult result, {
    String? onlyContactId,
  }) async {
    final now = DateTime.now();
    final medium = result.riskLevel == RiskLevel.medium;
    final incident = Incident(
      id: 'SUNO-${const Uuid().v4()}',
      detectionResult: result,
      status: medium
          ? IncidentStatus.safetyCheck
          : IncidentStatus.alertTriggered,
      createdAt: now,
      updatedAt: now,
      safetyCheckDeadline: medium
          ? now.add(_safetyCheckEngine.countdownDuration)
          : null,
    );
    await _serialize(() async {
      await _incidents.save(incident);
      _knownIncidents[incident.id] = incident;
      currentIncident = incident;
    });
    operationError = null;
    if (medium) {
      _beginSafetyCheck(incident);
    } else {
      _dispatchInBackground(incident.id, onlyContactId: onlyContactId);
    }
    _changed();
    return incident;
  }

  void _beginSafetyCheck(Incident incident) {
    if (_safetyIncidentId == incident.id) return;
    _safetyIncidentId = incident.id;
    _safetySaveFailed = false;
    operationError = null;
    final deadline =
        incident.safetyCheckDeadline ??
        incident.createdAt.add(_safetyCheckEngine.countdownDuration);
    final remaining = deadline.difference(DateTime.now());
    _safetyTask = _safetyCheckEngine
        .startCountdown(
          incident.detectionResult,
          remaining: remaining.isNegative ? Duration.zero : remaining,
        )
        .then((result) async {
          if (_disposed || _safetyIncidentId != incident.id) return;
          if (result.outcome == SafetyCheckOutcome.cancelled) {
            _safetyIncidentId = null;
            return;
          }
          final safe = result.outcome == SafetyCheckOutcome.userConfirmedSafe;
          final updated = await _serialize(() async {
            final existing = _knownIncidents[incident.id];
            if (existing == null ||
                existing.status != IncidentStatus.safetyCheck) {
              return null;
            }
            return _storeUpdate(
              existing.copyWith(
                detectionResult: result.detectionResult,
                status: safe
                    ? IncidentStatus.cancelled
                    : IncidentStatus.alertTriggered,
                updatedAt: DateTime.now(),
                contactResponseText: safe
                    ? 'User confirmed safe'
                    : 'Safety check escalated',
              ),
            );
          });
          _safetyIncidentId = null;
          if (!safe && updated != null) _dispatchInBackground(updated.id);
          _changed();
        })
        .catchError((Object _) {
          _safetySaveFailed = true;
          operationError = 'Could not save your safety decision. No alert was sent. Retry below or seek help another way.';
          _changed();
        });
  }

  void _retrySafetySave(String incidentId) {
    if (_safetyIncidentId != incidentId || !_safetySaveFailed) return;
    final incident = _knownIncidents[incidentId]!;
    _safetyIncidentId = null;
    _beginSafetyCheck(incident);
  }

  void confirmSafe(String incidentId) {
    _retrySafetySave(incidentId);
    if (_safetyIncidentId == incidentId) _safetyCheckEngine.confirmSafe();
  }

  void escalateSafetyCheck(String incidentId) {
    _retrySafetySave(incidentId);
    if (_safetyIncidentId == incidentId) _safetyCheckEngine.escalateNow();
  }

  Future<Incident> _storeUpdate(Incident incident) async {
    await _incidents.update(incident);
    _knownIncidents[incident.id] = incident;
    if (currentIncident?.id == incident.id) currentIncident = incident;
    return incident;
  }

  Future<Incident?> updateStatus(
    IncidentStatus status, [
    String? response,
    String? incidentId,
  ]) async {
    final id = incidentId ?? currentIncident?.id;
    if (id == null) return null;
    final updated = await _serialize(() async {
      final existing = _knownIncidents[id];
      if (existing == null) return null;
      return _storeUpdate(
        existing.copyWith(
          status: status,
          contactResponseText: response,
          updatedAt: DateTime.now(),
        ),
      );
    });
    _changed();
    return updated;
  }

  Future<List<Incident>> getIncidentHistory() => _serialize(() async {
    final history = await _incidents.getAll();
    _knownIncidents.addEntries(
      history.map((incident) => MapEntry(incident.id, incident)),
    );
    return history;
  });

  Future<void> removeIncident(String id) async {
    if (_safetyIncidentId == id || isDispatching(id)) {
      throw StateError('Finish the active safety action before deleting it.');
    }
    await _serialize(() async {
      await _incidents.remove(id);
      _deleted.add(id);
      _knownIncidents.remove(id);
      if (currentIncident?.id == id) currentIncident = null;
    });
    _changed();
  }

  Future<void> clearIncidentHistory() async {
    if (hasPendingSafetyCheck || _dispatches.isNotEmpty) {
      throw StateError(
        'Finish the active safety action before clearing history.',
      );
    }
    await _serialize(() async {
      await _incidents.clear();
      _deleted.addAll(_knownIncidents.keys);
      _knownIncidents.clear();
      currentIncident = null;
      receivedAlert = null;
    });
    _changed();
  }

  Future<Incident?> acceptReceivedAlert(ReceivedAlert alert) async {
    final id = alert.incidentId;
    if (id == null ||
        id.trim().isEmpty ||
        id.length > 128 ||
        _deleted.contains(id) ||
        alert.eventType == null ||
        alert.eventType!.trim().isEmpty) {
      return null;
    }
    final incident = await _serialize(() async {
      if (await _incidents.isDeleted(id)) return null;
      final existing = _knownIncidents[id];
      if (existing != null) return existing.isReceived ? existing : null;
      final now = DateTime.now();
      final detectedAt = DateTime.tryParse(alert.detectedAt ?? '') ?? now;
      final latitude = double.tryParse(alert.latitude ?? '');
      final longitude = double.tryParse(alert.longitude ?? '');
      final validCoordinates =
          latitude != null &&
          longitude != null &&
          latitude.isFinite &&
          longitude.isFinite &&
          latitude.abs() <= 90 &&
          longitude.abs() <= 180;
      final score = (int.tryParse(alert.riskScore ?? '') ?? 100)
          .clamp(0, 100)
          .toInt();
      final received = Incident(
        id: id,
        detectionResult: DetectionResult(
          eventType: alert.eventType ?? 'Emergency Alert',
          confidence: 1,
          impactDetected: false,
          stillnessDetected: false,
          riskScore: score,
          riskLevel: switch (alert.riskLevel) {
            'low' => RiskLevel.low,
            'medium' => RiskLevel.medium,
            _ => RiskLevel.critical,
          },
          latitude: validCoordinates ? latitude : null,
          longitude: validCoordinates ? longitude : null,
          locationText: alert.location,
          detectedAt: detectedAt,
          isSimulated: alert.isSimulated,
        ),
        status: IncidentStatus.alertTriggered,
        createdAt: detectedAt,
        updatedAt: now,
        origin: 'Trusted Contact',
        senderToken: alert.senderToken,
      );
      await _incidents.save(received);
      _knownIncidents[id] = received;
      return received;
    });
    receivedAlert = alert;
    _changed();
    return incident;
  }

  Future<void> sendResponse({
    required String recipientToken,
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  }) async {
    final service = _alertService;
    if (service == null || recipientToken.trim().isEmpty) {
      throw StateError(
        'The sender cannot be reached: response routing is unavailable.',
      );
    }
    await service.sendResponse(
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

  Future<bool> testContactNotification(TrustedContact contact) async {
    final service = _alertService;
    final token = contact.fcmToken?.trim();
    if (service == null || token == null || token.isEmpty) return false;
    final accepted = await service.sendTestMessage(token);
    if (accepted) {
      final saved = (await _contacts.getAll())
          .where((value) => value.id == contact.id)
          .firstOrNull;
      if (saved != null && saved.fcmToken?.trim() == token) {
        await _contacts.update(
          TrustedContact(
            id: saved.id,
            name: saved.name,
            phone: saved.phone,
            relationship: saved.relationship,
            fcmToken: saved.fcmToken,
            verifiedAt: DateTime.now(),
          ),
        );
      }
    }
    return accepted;
  }

  void _dispatchInBackground(String id, {String? onlyContactId}) {
    unawaited(
      dispatchIncident(id, onlyContactId: onlyContactId).catchError((Object _) {
        operationError = 'The alert could not be completed. Check the saved incident and retry.';
        _changed();
        return const AlertDispatchResult(
          success: false,
          attemptedCount: 0,
          failedReason: 'Could not save the delivery result',
        );
      }),
    );
  }

  Future<AlertDispatchResult> dispatchIncident(
    String id, {
    String? onlyContactId,
  }) {
    final pending = _dispatches[id];
    if (pending != null) return pending;
    final future = _dispatch(id, onlyContactId: onlyContactId).whenComplete(() {
      _dispatches.remove(id);
      _changed();
    });
    _dispatches[id] = future;
    _changed();
    return future;
  }

  Future<AlertDispatchResult> _dispatch(
    String id, {
    String? onlyContactId,
  }) async {
    await _mutations;
    final incident = _knownIncidents[id];
    final service = _alertService;
    if (incident == null ||
        incident.isReceived ||
        incident.status == IncidentStatus.cancelled ||
        incident.status == IncidentStatus.resolved) {
      return const AlertDispatchResult(
        success: false,
        attemptedCount: 0,
        failedReason: 'No active outgoing incident',
      );
    }
    AlertDispatchResult result;
    var attempted = 0;
    try {
      final contacts = (await _contacts.getAll()).where(
        (contact) => onlyContactId == null || contact.id == onlyContactId,
      );
      final tokens = contacts
          .map((contact) => contact.fcmToken?.trim())
          .whereType<String>()
          .where((token) => token.isNotEmpty)
          .toSet()
          .toList();
      attempted = tokens.length;
      if (service == null || tokens.isEmpty) {
        result = AlertDispatchResult(
          success: false,
          attemptedCount: attempted,
          failedReason: service == null
              ? 'Alert service unavailable'
              : 'No contacts with a push token',
        );
      } else {
        final detection = incident.detectionResult;
        final sent = await service.sendAlert(
          contactTokens: tokens,
          payload: {
            'incidentId': id,
            'eventType': detection.eventType,
            'riskScore': detection.riskScore.toString(),
            'riskLevel': detection.riskLevel.wireValue,
            'detectedAt': detection.detectedAt.toIso8601String(),
            'isSimulated': detection.isSimulated.toString(),
            if (detection.latitude != null)
              'latitude': detection.latitude.toString(),
            if (detection.longitude != null)
              'longitude': detection.longitude.toString(),
            if (detection.locationText != null)
              'locationText': detection.locationText!,
            if (service.deviceToken != null)
              'senderToken': service.deviceToken!,
          },
        );
        if (sent < 0 || sent > attempted) {
          throw StateError('Invalid relay result');
        }
        result = AlertDispatchResult(
          success: sent == attempted,
          attemptedCount: attempted,
          sentCount: sent,
          failedReason: sent == attempted
              ? null
              : 'FCM accepted $sent/$attempted alerts',
        );
      }
    } catch (_) {
      result = AlertDispatchResult(
        success: false,
        attemptedCount: attempted,
        failedReason: 'Delivery failed. Check connectivity, relay configuration, and contact tokens.',
      );
    }
    await _serialize(() async {
      final existing = _knownIncidents[id];
      if (existing == null) return;
      await _storeUpdate(
        existing.copyWith(
          dispatchResult: result,
          updatedAt: DateTime.now(),
          status:
              result.sentCount > 0 &&
                  existing.status == IncidentStatus.alertTriggered
              ? IncidentStatus.contactNotified
              : existing.status,
        ),
      );
    });
    return result;
  }

  Future<Incident?> triggerManualAlert({String? onlyContactId}) async {
    if (_recording != null) return _recording;
    if (hasPendingDispatch) return currentIncident;
    if (hasPendingSafetyCheck) {
      final id = _safetyIncidentId!;
      escalateSafetyCheck(id);
      await safetyCheckCompleted;
      return _knownIncidents[id];
    }
    final future = () async {
      final position = await refreshLocation();
      return _record(
        DetectionResult(
          eventType: 'Manual Silent Alert',
          confidence: 1,
          impactDetected: false,
          stillnessDetected: false,
          riskScore: 100,
          riskLevel: RiskLevel.critical,
          latitude: position?.latitude,
          longitude: position?.longitude,
          locationText: position?.description,
          detectedAt: DateTime.now(),
        ),
        onlyContactId: onlyContactId,
      );
    }();
    _recording = future;
    try {
      return await future;
    } finally {
      _recording = null;
    }
  }

  Future<bool> applyContactResponse({
    required String incidentId,
    required String responderName,
    required String status,
    required String message,
  }) async {
    if (!['resolved', 'alertTriggered', 'contactChecking'].contains(status)) {
      return false;
    }
    final updated = await _serialize(() async {
      final existing = _knownIncidents[incidentId];
      if (existing == null ||
          existing.isReceived ||
          existing.status == IncidentStatus.cancelled) {
        return false;
      }
      final nextStatus = switch (status) {
        'resolved' => IncidentStatus.resolved,
        'alertTriggered' => IncidentStatus.alertTriggered,
        _ => IncidentStatus.contactChecking,
      };
      final text = '$responderName: $message';
      if (existing.status == nextStatus &&
          existing.contactResponseText == text) {
        return true;
      }
      if (existing.status == IncidentStatus.resolved) return true;
      await _storeUpdate(
        existing.copyWith(
          status: nextStatus,
          contactResponseText: text,
          updatedAt: DateTime.now(),
        ),
      );
      return true;
    });
    _changed();
    return updated;
  }

  @override
  void dispose() {
    _disposed = true;
    _safetyIncidentId = null;
    _safetyCheckEngine.dispose();
    super.dispose();
  }
}
