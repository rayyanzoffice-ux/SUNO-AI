import '../../models/detection_result.dart';

/// Fixed scoring weights used by [RiskEngine]. Kept as named constants (not
/// magic numbers) so the two of you can tune them during testing without
/// hunting through the scoring logic itself. Mirrors the additive model in
/// SUNO_Architecture_and_Roadmap.docx §5, adapted to the signals actually
/// present on [DetectionResult] per API_CONTRACT.md.
class RiskWeights {
  const RiskWeights._();

  /// Awarded when the on-device classifier reports high-confidence distress
  /// audio (scream, alarm, glass breaking, etc.) for the current event. A
  /// high-confidence reading alone is enough to reach the medium band and
  /// trigger the Safety Check — see [RiskThresholds.mediumFloor].
  static const int highConfidenceDistress = 50;

  /// Awarded for a moderate-confidence distress reading. Deliberately below
  /// [RiskThresholds.mediumFloor] on its own — a moderate reading with no
  /// motion corroboration isn't enough to interrupt the user.
  static const int moderateConfidenceDistress = 35;

  /// Awarded when the accelerometer reports a sudden impact alongside the
  /// audio event (phone dropped, struck, etc.).
  static const int impactDetected = 30;

  /// Awarded when the phone stops moving right after the event — consistent
  /// with the user being incapacitated rather than continuing normal motion.
  static const int stillnessDetected = 15;

  /// Awarded only during the Safety Check flow, when the 10-second "are you
  /// safe?" countdown expires with no user response. Applied by
  /// [RiskEngine.escalateForNoResponse], never by [RiskEngine.evaluateDetection].
  static const int noResponseToSafetyCheck = 20;

  /// Confidence value (0.0–1.0) at or above which a distress reading counts
  /// as "high confidence" rather than "moderate confidence".
  static const double highConfidenceThreshold = 0.80;

  /// Confidence value below which a distress reading is too weak to score
  /// at all — treated as ambient/normal sound, per architecture doc §4.2
  /// step 4 (below-threshold results are coerced to "normal").
  static const double minimumConfidenceThreshold = 0.60;
}

/// The two thresholds that separate low / medium / critical risk. Matches
/// API_CONTRACT.md's Risk Levels table exactly — do not change these here
/// without updating that file too.
class RiskThresholds {
  const RiskThresholds._();
  static const int mediumFloor = 40;
  static const int criticalFloor = 70;
  static const int maxScore = 100;
}

/// Immutable result of a single risk evaluation — the score plus the derived
/// [RiskLevel], returned together so callers never end up with one without
/// the other and risk them drifting apart.
class RiskAssessment {
  const RiskAssessment({required this.riskScore, required this.riskLevel});

  final int riskScore;
  final RiskLevel riskLevel;

  @override
  String toString() =>
      'RiskAssessment(riskScore: $riskScore, riskLevel: ${riskLevel.wireValue})';
}

/// Deterministic, explainable risk-scoring engine.
///
/// Framework-free by design: no [Widget], no [BuildContext], no sensor or
/// network calls — just numbers in, numbers out. This is what lets it be
/// unit-tested in isolation (see test/risk_engine_test.dart) and reasoned
/// about by either teammate without the Flutter app running at all.
class RiskEngine {
  const RiskEngine();

  /// Scores a fresh detection event from the on-device classifier output and
  /// motion signals. Called once per detection, before any Safety Check
  /// countdown has run — [RiskWeights.noResponseToSafetyCheck] is never
  /// included here. Call [escalateForNoResponse] afterwards if a countdown
  /// started from this result later expires.
  RiskAssessment evaluateDetection({
    required double confidence,
    required bool impactDetected,
    required bool stillnessDetected,
  }) {
    final score = _clampScore(
      _distressScoreFor(confidence) +
          (impactDetected ? RiskWeights.impactDetected : 0) +
          (stillnessDetected ? RiskWeights.stillnessDetected : 0),
    );
    return RiskAssessment(riskScore: score, riskLevel: _levelFor(score));
  }

  /// Re-scores an existing assessment after a Safety Check countdown expires
  /// with no user response, adding [RiskWeights.noResponseToSafetyCheck] and
  /// re-deriving the risk level from the new total. This is what can turn a
  /// medium detection into a critical one, per the escalation flow in
  /// SUNO_Architecture_and_Roadmap.docx §2.1 step 5.
  RiskAssessment escalateForNoResponse(RiskAssessment previous) {
    final score = _clampScore(
      previous.riskScore + RiskWeights.noResponseToSafetyCheck,
    );
    return RiskAssessment(riskScore: score, riskLevel: _levelFor(score));
  }

  int _distressScoreFor(double confidence) {
    if (confidence >= RiskWeights.highConfidenceThreshold) {
      return RiskWeights.highConfidenceDistress;
    }
    if (confidence >= RiskWeights.minimumConfidenceThreshold) {
      return RiskWeights.moderateConfidenceDistress;
    }
    // Below threshold — treated as ambient/normal sound, contributes nothing.
    return 0;
  }

  RiskLevel _levelFor(int score) {
    if (score >= RiskThresholds.criticalFloor) return RiskLevel.critical;
    if (score >= RiskThresholds.mediumFloor) return RiskLevel.medium;
    return RiskLevel.low;
  }

  /// Manual min/max instead of num.clamp — num.clamp's static return type is
  /// `num`, not `int`, which would force a cast everywhere this is used.
  /// Writing it out keeps every call site cleanly typed as int.
  int _clampScore(int rawScore) {
    if (rawScore < 0) return 0;
    if (rawScore > RiskThresholds.maxScore) return RiskThresholds.maxScore;
    return rawScore;
  }
}
