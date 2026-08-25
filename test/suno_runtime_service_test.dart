import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/backend_exports.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/services/suno_runtime_service.dart';

void main() {
  test(
    'SafetyCheckEngine timeout escalates medium detection to critical',
    () async {
      final runtime = SunoRuntimeService(
        safetyCheckEngine: SafetyCheckEngine(
          countdownDuration: const Duration(milliseconds: 5),
        ),
      );
      final medium = await runtime.runDetection(DetectionScenario.medium);
      await runtime.recordDetection(medium);

      final outcome = await runtime.startSafetyCheck();
      await runtime.applySafetyCheckResult(outcome);

      expect(outcome.outcome, SafetyCheckOutcome.noResponse);
      expect(outcome.detectionResult.riskScore, 70);
      expect(outcome.detectionResult.riskLevel, RiskLevel.critical);
      expect(runtime.currentIncident?.status, IncidentStatus.alertTriggered);
    },
  );

  test('runtime exposes contacts from trusted contact repository', () async {
    final contacts = await SunoRuntimeService().getTrustedContacts();
    expect(contacts, hasLength(1));
    expect(contacts.single.relationship, 'Brother');
  });
}
