import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/risk/risk_engine.dart';
import 'package:suno_ai/models/detection_result.dart';

void main() {
  const engine = RiskEngine();

  group('RiskEngine.evaluateDetection', () {
    test('high-confidence distress + impact + stillness lands in critical', () {
      final result = engine.evaluateDetection(
        confidence: 0.93,
        impactDetected: true,
        stillnessDetected: true,
      );
      expect(result.riskScore, 95); // 50 + 30 + 15
      expect(result.riskLevel, RiskLevel.critical);
    });

    test(
      'high-confidence distress alone (no motion corroboration) lands in medium',
      () {
        final result = engine.evaluateDetection(
          confidence: 0.85,
          impactDetected: false,
          stillnessDetected: false,
        );
        expect(result.riskScore, 50);
        expect(result.riskLevel, RiskLevel.medium);
      },
    );

    test('moderate-confidence sound alone is too weak to clear the medium floor', () {
      final result = engine.evaluateDetection(
        confidence: 0.65,
        impactDetected: false,
        stillnessDetected: false,
      );
      expect(result.riskScore, 35);
      expect(result.riskLevel, RiskLevel.low);
    });

    test('low-confidence ambient sound scores zero and stays low risk', () {
      final result = engine.evaluateDetection(
        confidence: 0.20,
        impactDetected: false,
        stillnessDetected: false,
      );
      expect(result.riskScore, 0);
      expect(result.riskLevel, RiskLevel.low);
    });
  });

  group('RiskEngine.escalateForNoResponse', () {
    test('adds the no-response weight and can push medium into critical', () {
      const mediumAssessment = RiskAssessment(
        riskScore: 55,
        riskLevel: RiskLevel.medium,
      );
      final escalated = engine.escalateForNoResponse(mediumAssessment);
      expect(escalated.riskScore, 75);
      expect(escalated.riskLevel, RiskLevel.critical);
    });

    test('clamps at 100 when escalating an already-high score', () {
      const highAssessment = RiskAssessment(
        riskScore: 95,
        riskLevel: RiskLevel.critical,
      );
      final escalated = engine.escalateForNoResponse(highAssessment);
      expect(escalated.riskScore, 100);
      expect(escalated.riskLevel, RiskLevel.critical);
    });
  });
}
