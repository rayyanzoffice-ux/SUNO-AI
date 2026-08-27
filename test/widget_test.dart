import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/app.dart';
import 'package:suno_ai/backend/backend_exports.dart';
import 'package:suno_ai/core/routes/app_routes.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/screens/emergency_alert/emergency_alert_screen.dart';
import 'package:suno_ai/screens/history/history_screen.dart';
import 'package:suno_ai/screens/monitoring/monitoring_screen.dart';
import 'package:suno_ai/screens/safety_check/safety_check_screen.dart';
import 'package:suno_ai/screens/trusted_contact/trusted_contact_view_screen.dart';
import 'package:suno_ai/services/suno_runtime_service.dart';

void main() {
  testWidgets('home offers the critical demo entry points', (tester) async {
    await tester.pumpWidget(const SunoApp());
    expect(find.text('SUNO'), findsOneWidget);
    expect(find.text('START MONITORING'), findsOneWidget);
    expect(find.text('Trusted Contacts'), findsOneWidget);
  });

  testWidgets('low detection remains on Monitoring', (tester) async {
    await _pumpScenario(tester, DetectionScenario.low);
    await tester.tap(find.text('Demo: Simulate Distress'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('SUNO is Active'), findsOneWidget);
    expect(find.text('Emergency Alert Activated'), findsNothing);
    expect(find.text('Are you safe?'), findsNothing);
  });

  testWidgets('medium detection opens Safety Check and safe cancels incident', (
    tester,
  ) async {
    await _pumpScenario(tester, DetectionScenario.medium);
    await tester.tap(find.text('Demo: Simulate Distress'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Are you safe?'), findsOneWidget);
    await tester.tap(find.text('I AM SAFE'));
    await tester.pumpAndSettle();

    expect(find.text('Incident History'), findsOneWidget);
    expect(
      SunoRuntimeService.instance.currentIncident?.status,
      IncidentStatus.cancelled,
    );
    expect(find.text('Possible Distress Sound'), findsWidgets);
  });

  testWidgets('critical detection opens Emergency Alert immediately', (
    tester,
  ) async {
    await _pumpScenario(tester, DetectionScenario.critical);
    await tester.tap(find.text('Demo: Simulate Distress'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Emergency Alert Activated'), findsOneWidget);
    expect(find.text('95% (Critical)'), findsOneWidget);

    await tester.ensureVisible(find.text('VIEW LOCATION'));
    await tester.tap(find.text('VIEW LOCATION'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I AM CHECKING ON THEM'));
    await tester.tap(find.text('I AM CHECKING ON THEM'));
    await tester.pumpAndSettle();
    expect(
      SunoRuntimeService.instance.currentIncident?.status,
      IncidentStatus.contactChecking,
    );

    await tester.ensureVisible(find.text('VIEW HISTORY'));
    await tester.tap(find.text('VIEW HISTORY'));
    await tester.pumpAndSettle();
    expect(find.text('Contact checking'), findsOneWidget);
    expect(find.text('Distress Sound + Impact'), findsOneWidget);
  });

  testWidgets('history shows empty state without fabricated incidents', (
    tester,
  ) async {
    final runtime = SunoRuntimeService(
      incidentRepository: InMemoryIncidentRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(runtimeService: runtime)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No incidents yet'), findsOneWidget);
    expect(find.text('61%'), findsNothing);
    expect(find.text('58%'), findsNothing);
  });

  testWidgets('history uses repository data and status filters', (
    tester,
  ) async {
    final repository = InMemoryIncidentRepository();
    final runtime = SunoRuntimeService(incidentRepository: repository);
    final cancelled = _historyIncident(
      id: 'cancelled',
      eventType: 'Cancelled Demo Event',
      riskScore: 50,
      status: IncidentStatus.cancelled,
      createdAt: DateTime(2026, 8, 26, 20),
    );
    final critical = _historyIncident(
      id: 'critical',
      eventType: 'Critical Demo Event',
      riskScore: 95,
      status: IncidentStatus.alertTriggered,
      createdAt: DateTime(2026, 8, 26, 21),
    );
    await repository.save(cancelled);
    await repository.save(critical);

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(runtimeService: runtime)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Critical Demo Event'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('Cancelled Demo Event'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Critical Demo Event')).dy,
      lessThan(tester.getTopLeft(find.text('Cancelled Demo Event')).dy),
    );

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('Critical Demo Event'), findsOneWidget);
    expect(find.text('Cancelled Demo Event'), findsNothing);

    await tester.tap(find.text('Canceled'));
    await tester.pumpAndSettle();
    expect(find.text('Critical Demo Event'), findsNothing);
    expect(find.text('Cancelled Demo Event'), findsOneWidget);
    expect(find.text('61%'), findsNothing);
    expect(find.text('58%'), findsNothing);
  });

  test('backend mock inputs still produce the API contract values', () async {
    final result = await SunoRuntimeService.instance.runDetection(
      DetectionScenario.critical,
    );
    final json = result.toJson(status: IncidentStatus.alertTriggered.wireValue);

    expect(json['riskLevel'], 'critical');
    expect(json['locationText'], 'Lahore, Pakistan');
    expect(json['status'], 'alert_triggered');
    expect(json['riskScore'], 95);
  });
}

Incident _historyIncident({
  required String id,
  required String eventType,
  required int riskScore,
  required IncidentStatus status,
  required DateTime createdAt,
}) => Incident(
  id: id,
  detectionResult: DetectionResult(
    eventType: eventType,
    confidence: .9,
    impactDetected: riskScore >= 70,
    stillnessDetected: false,
    riskScore: riskScore,
    riskLevel: riskScore >= 70 ? RiskLevel.critical : RiskLevel.medium,
    detectedAt: createdAt,
  ),
  status: status,
  createdAt: createdAt,
  updatedAt: createdAt,
);

Future<void> _pumpScenario(WidgetTester tester, DetectionScenario scenario) =>
    tester.pumpWidget(
      MaterialApp(
        home: MonitoringScreen(scenario: scenario),
        routes: {
          AppRoutes.safetyCheck: (_) => const SafetyCheckScreen(),
          AppRoutes.emergencyAlert: (_) => const EmergencyAlertScreen(),
          AppRoutes.trustedContactView: (_) => const TrustedContactViewScreen(),
          AppRoutes.history: (_) => const HistoryScreen(),
        },
      ),
    );
