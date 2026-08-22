// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/app.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/services/mock_detection_service.dart';
import 'package:suno_ai/services/mock_incident_service.dart';

void main() {
  testWidgets('home offers the critical demo entry points', (tester) async {
    await tester.pumpWidget(const SunoApp());
    expect(find.text('SUNO'), findsOneWidget);
    expect(find.text('START MONITORING'), findsOneWidget);
    expect(find.text('Trusted Contacts'), findsOneWidget);
  });

  testWidgets('critical demo flow records contact checking in history', (
    tester,
  ) async {
    await tester.pumpWidget(const SunoApp());
    await tester.tap(find.text('START MONITORING'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SIMULATE DISTRESS DETECTION'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Emergency Alert Activated'), findsOneWidget);

    await tester.ensureVisible(find.text('VIEW TRUSTED CONTACT ALERT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VIEW TRUSTED CONTACT ALERT'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I AM CHECKING ON THEM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I AM CHECKING ON THEM'));
    await tester.pump();
    await tester.ensureVisible(find.text('VIEW HISTORY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VIEW HISTORY'));
    await tester.pumpAndSettle();
    expect(find.text('Contact checking'), findsOneWidget);
  });

  test('models expose API contract wire values', () {
    final result = MockDetectionService().createCriticalDemoResult();
    final json = result.toJson(status: IncidentStatus.alertTriggered.wireValue);

    expect(json['riskLevel'], 'critical');
    expect(json['locationText'], 'Lahore, Pakistan');
    expect(json['status'], 'alert_triggered');
    expect(DetectionResult.fromJson(json).riskScore, 96);
  });

  tearDown(() => MockIncidentService.instance.currentIncident = null);
}
