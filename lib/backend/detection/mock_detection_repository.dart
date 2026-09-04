import '../../models/detection_result.dart';
import '../risk/risk_engine.dart';
import 'detection_repository.dart';

/// Demo-safe stand-in for the real on-device classifier + motion pipeline.
class MockDetectionRepository implements DetectionRepository {
  MockDetectionRepository({RiskEngine? riskEngine})
    : _riskEngine = riskEngine ?? const RiskEngine();

  final RiskEngine _riskEngine;

  static const _demoLatitude = 31.5204;
  static const _demoLongitude = 74.3587;
  static const _demoLocationText = 'Lahore, Pakistan';

  Future<DetectionResult> simulateCriticalDetection() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _buildResult(
      eventType: 'Distress Sound + Impact',
      detectedClass: 'distress_voice',
      confidence: 0.93,
      impactDetected: true,
      stillnessDetected: true,
    );
  }

  Future<DetectionResult> simulateMediumDetection() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _buildResult(
      eventType: 'Possible Distress Sound',
      detectedClass: 'distress_voice',
      confidence: 0.85,
      impactDetected: false,
      stillnessDetected: false,
    );
  }

  Future<DetectionResult> simulateLowRiskDetection() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _buildResult(
      eventType: 'Ambient Sound',
      detectedClass: 'ambient_safe',
      confidence: 0.20,
      impactDetected: false,
      stillnessDetected: false,
    );
  }

  @override
  Future<DetectionResult> detect() => simulateCriticalDetection();

  DetectionResult _buildResult({
    required String eventType,
    required String detectedClass,
    required double confidence,
    required bool impactDetected,
    required bool stillnessDetected,
  }) {
    final assessment = _riskEngine.evaluateDetection(
      detectedClass: detectedClass,
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
