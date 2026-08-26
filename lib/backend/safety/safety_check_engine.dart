import 'dart:async';

import '../../models/detection_result.dart';
import '../risk/risk_engine.dart';

/// Outcome of a completed Safety Check countdown.
enum SafetyCheckOutcome { userConfirmedSafe, noResponse, cancelled }

/// Bundles the outcome with the (possibly escalated) [DetectionResult] so
/// the caller has everything needed to update the Incident in one step.
class SafetyCheckResult {
  const SafetyCheckResult({
    required this.outcome,
    required this.detectionResult,
  });

  final SafetyCheckOutcome outcome;
  final DetectionResult detectionResult;
}

/// Runs the "Are you safe?" countdown for medium-risk detections and
/// escalates the risk score/level if the user doesn't respond in time.
///
/// Framework-free — screens/state controllers own the actual UI countdown
/// display (the visible "10" ring) and call into this class only for the
/// timing + scoring logic. Only one countdown can be active at a time.
class SafetyCheckEngine {
  SafetyCheckEngine({RiskEngine? riskEngine, Duration? countdownDuration})
    : _riskEngine = riskEngine ?? const RiskEngine(),
      _countdownDuration = countdownDuration ?? const Duration(seconds: 10);

  final RiskEngine _riskEngine;
  final Duration _countdownDuration;

  Timer? _timer;
  Completer<SafetyCheckResult>? _pendingCompleter;
  DetectionResult? _pendingDetection;

  /// Starts the countdown for [detection]. The returned future resolves
  /// with [SafetyCheckOutcome.noResponse] and an escalated [DetectionResult]
  /// if [confirmSafe] isn't called before the countdown elapses, or with
  /// [SafetyCheckOutcome.userConfirmedSafe] and the original (unescalated)
  /// result if it is.
  Future<SafetyCheckResult> startCountdown(DetectionResult detection) {
    _cancelActiveCountdown();
    final completer = Completer<SafetyCheckResult>();
    _pendingCompleter = completer;
    _pendingDetection = detection;

    _timer = Timer(_countdownDuration, () {
      final pending = _pendingDetection;
      if (pending == null || completer.isCompleted) return;
      final escalated = _escalate(pending);
      completer.complete(
        SafetyCheckResult(
          outcome: SafetyCheckOutcome.noResponse,
          detectionResult: escalated,
        ),
      );
      _clearPending();
    });

    return completer.future;
  }

  /// Call when the user taps "I am safe" — cancels the countdown and
  /// resolves the pending future with the original, non-escalated result.
  /// No-ops if there is no countdown currently running.
  void confirmSafe() {
    final completer = _pendingCompleter;
    final pending = _pendingDetection;
    if (completer == null || pending == null || completer.isCompleted) return;
    _timer?.cancel();
    completer.complete(
      SafetyCheckResult(
        outcome: SafetyCheckOutcome.userConfirmedSafe,
        detectionResult: pending,
      ),
    );
    _clearPending();
  }

  /// Immediately completes the active check as no-response. This is used by
  /// the explicit "can't respond" action and keeps escalation in this engine.
  void escalateNow() {
    final completer = _pendingCompleter;
    final pending = _pendingDetection;
    if (completer == null || pending == null || completer.isCompleted) return;
    _timer?.cancel();
    completer.complete(
      SafetyCheckResult(
        outcome: SafetyCheckOutcome.noResponse,
        detectionResult: _escalate(pending),
      ),
    );
    _clearPending();
  }

  /// Cancels any in-flight countdown and resolves its future as cancelled.
  /// This prevents callers awaiting [startCountdown] from being left hanging
  /// when the owning screen is disposed. Cancellation is deliberately not
  /// treated as no-response, so it cannot trigger an emergency escalation.
  void dispose() {
    final completer = _pendingCompleter;
    final pending = _pendingDetection;
    _timer?.cancel();
    _timer = null;
    if (completer != null && pending != null && !completer.isCompleted) {
      completer.complete(
        SafetyCheckResult(
          outcome: SafetyCheckOutcome.cancelled,
          detectionResult: pending,
        ),
      );
    }
    _pendingCompleter = null;
    _pendingDetection = null;
  }

  DetectionResult _escalate(DetectionResult detection) {
    final previousAssessment = RiskAssessment(
      riskScore: detection.riskScore,
      riskLevel: detection.riskLevel,
    );
    final escalated = _riskEngine.escalateForNoResponse(previousAssessment);
    return DetectionResult(
      eventType: detection.eventType,
      confidence: detection.confidence,
      impactDetected: detection.impactDetected,
      stillnessDetected: detection.stillnessDetected,
      riskScore: escalated.riskScore,
      riskLevel: escalated.riskLevel,
      latitude: detection.latitude,
      longitude: detection.longitude,
      locationText: detection.locationText,
      detectedAt: detection.detectedAt,
    );
  }

  void _clearPending() {
    _pendingCompleter = null;
    _pendingDetection = null;
    _timer = null;
  }

  void _cancelActiveCountdown() {
    final completer = _pendingCompleter;
    final pending = _pendingDetection;
    _timer?.cancel();
    if (completer != null && pending != null && !completer.isCompleted) {
      completer.complete(
        SafetyCheckResult(
          outcome: SafetyCheckOutcome.cancelled,
          detectionResult: pending,
        ),
      );
    }
    _clearPending();
  }
}
