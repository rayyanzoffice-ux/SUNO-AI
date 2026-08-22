import '../models/detection_result.dart';

class MockDetectionService {
  DetectionResult createCriticalDemoResult() => DetectionResult(
    eventType: 'Distress Sound + Impact',
    confidence: 0.93,
    impactDetected: true,
    stillnessDetected: true,
    riskScore: 96,
    riskLevel: RiskLevel.critical,
    latitude: 31.5204,
    longitude: 74.3587,
    locationText: 'Lahore, Pakistan',
    detectedAt: DateTime.now(),
  );

  // TODO: Replace mock detection with backend/AI DetectionResult integration.
  Future<DetectionResult> simulateCriticalDetection() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return createCriticalDemoResult();
  }
}
