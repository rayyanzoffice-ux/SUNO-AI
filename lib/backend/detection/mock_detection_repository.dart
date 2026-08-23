import '../../models/detection_result.dart';
import '../risk/risk_engine.dart';
import 'detection_repository.dart';

/// Demo-safe stand-in for the real on-device classifier + motion pipeline.
/// Produces three named scenarios — critical, medium, and low — so every
/// risk band can be demoed and tested without the real TFLite model wired
/// up yet. Real risk scoring still runs underneath via [RiskEngine], so
/// these aren't hardcoded outcomes — only the raw "sensor" inputs are.
class MockDetectionRepository implements DetectionRepository {
  MockDetectionRepository({RiskEngine? riskEngine})
    : _riskEngine = riskEngine ?? const RiskEngine();

  final RiskEngine _riskEngine;

  static const _demoLatitude = 31.5204;
  static const _demoLongitude = 74.3587;
  static const _demoLocationText = 'Lahore, Pakistan';

  /// The primary demo path: a high-confidence distress sound plus a
  /// detected impact and post-impact stillness. Scores as critical
  /// (0.93 confidence → +50, impact → +30, stillness → +15 = 95).
  Future<DetectionResult> simulateCriticalDetection() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _buildResult(
      eventType: 'Distress Sound + Impact',
      confidence: 0.93,
      impactDetected: true,
      stillnessDetected: true,
    );
  }

  /// A high-confidence distress sound with no motion corroboration. Scores
  /// as medium (0.85 confidence → +50, nothing else = 50), which should
  /// route the app to the Safety Check screen rather than an immediate
  /// alert.
  Future<DetectionResult> simulateMediumDetection() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _buildResult(
      eventType: 'Possible Distress Sound',
      confidence: 0.85,
      impactDetected: false,
      stillnessDetected: false,
    );
  }

  /// A low-confidence / ambient reading. Scores zero and should keep
  /// monitoring silently with no interruption.
  Future<DetectionResult> simulateLowRiskDetection() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _buildResult(
      eventType: 'Ambient Sound',
      confidence: 0.20,
      impactDetected: false,
      stillnessDetected: false,
    );
  }

  @override
  Future<DetectionResult> detect() => simulateCriticalDetection();

  DetectionResult _buildResult({
    required String eventType,
    required double confidence,
    required bool impactDetected,
    required bool stillnessDetected,
  }) {
    final assessment = _riskEngine.evaluateDetection(
      confidence: confidence,
      impactDetected: impactDetected,
      stillnessDetected: stillnessDetected,
    );
    return DetectionResult(
      eventType: eventType,
      confidence: confidence,
      impactDetected: impactDetected,
      stillnessDetected: stillnessDetected,
      riskScore: assessment.riskScore,
      riskLevel: assessment.riskLevel,
      latitude: _demoLatitude,
      longitude: _demoLongitude,
      locationText: _demoLocationText,
      detectedAt: DateTime.now(),
    );
  }
}
