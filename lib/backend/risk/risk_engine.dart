import '../../models/detection_result.dart';

/// Audio class labels that carry distress evidence.
/// ambient_safe is intentionally absent — confidence for that class never
/// contributes to the risk score, preventing false alarms from background noise.
const _distressClasses = {'distress_voice', 'alarm_siren', 'breaking_crash'};

class RiskWeights {
  const RiskWeights._();
  static const int highConfidenceDistress = 50;
  static const int moderateConfidenceDistress = 35;
  static const int impactDetected = 30;
  static const int stillnessDetected = 15;
  static const int noResponseToSafetyCheck = 20;
  static const double highConfidenceThreshold = 0.80;
  static const double minimumConfidenceThreshold = 0.60;
}

class RiskThresholds {
  const RiskThresholds._();
  static const int mediumFloor = 40;
  static const int criticalFloor = 70;
  static const int maxScore = 100;
}

class RiskAssessment {
  const RiskAssessment({required this.riskScore, required this.riskLevel});
  final int riskScore;
  final RiskLevel riskLevel;

  @override
  String toString() =>
      'RiskAssessment(riskScore: $riskScore, riskLevel: ${riskLevel.wireValue})';
}

/// Deterministic, class-aware risk-scoring engine.
///
/// ambient_safe never contributes audio score regardless of confidence,
/// preventing high-confidence background noise from triggering alerts.
class RiskEngine {
  const RiskEngine();

  /// Scores a detection event. [detectedClass] must be one of the four
  /// SUNO classifier labels (ambient_safe, distress_voice, alarm_siren,
  /// breaking_crash). Only distress classes contribute an audio score.
  RiskAssessment evaluateDetection({
    required String detectedClass,
    required double confidence,
    required bool impactDetected,
    required bool stillnessDetected,
  }) {
    final audioScore = _distressClasses.contains(detectedClass)
        ? _distressScoreFor(confidence)
        : 0;
    final score = _clampScore(
      audioScore +
          (impactDetected ? RiskWeights.impactDetected : 0) +
          (stillnessDetected ? RiskWeights.stillnessDetected : 0),
    );
    return RiskAssessment(riskScore: score, riskLevel: _levelFor(score));
  }

  RiskAssessment escalateForNoResponse(RiskAssessment previous) {
    final score =
        _clampScore(previous.riskScore + RiskWeights.noResponseToSafetyCheck);
    return RiskAssessment(riskScore: score, riskLevel: _levelFor(score));
  }

  int _distressScoreFor(double confidence) {
    if (confidence >= RiskWeights.highConfidenceThreshold) {
      return RiskWeights.highConfidenceDistress;
    }
    if (confidence >= RiskWeights.minimumConfidenceThreshold) {
      return RiskWeights.moderateConfidenceDistress;
    }
    return 0;
  }

  RiskLevel _levelFor(int score) {
    if (score >= RiskThresholds.criticalFloor) return RiskLevel.critical;
    if (score >= RiskThresholds.mediumFloor) return RiskLevel.medium;
    return RiskLevel.low;
  }

  int _clampScore(int rawScore) {
    if (rawScore < 0) return 0;
    if (rawScore > RiskThresholds.maxScore) return RiskThresholds.maxScore;
    return rawScore;
  }
}
