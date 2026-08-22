import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/mock_incident_service.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/risk_badge.dart';

class EmergencyAlertScreen extends StatelessWidget {
  const EmergencyAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final incident = MockIncidentService.instance.currentIncident;
    final result = incident?.detectionResult;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.emergency.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emergency_rounded,
                  color: AppColors.emergency,
                  size: 58,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Emergency Alert Activated',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              const Text(
                'Critical risk detected. Your safety network is being engaged.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _row(
                        'Event',
                        result?.eventType ?? 'Distress Sound + Impact',
                      ),
                      _row(
                        'Confidence',
                        '${((result?.confidence ?? .93) * 100).round()}%',
                      ),
                      _row(
                        'Location',
                        result == null
                            ? MockIncidentService.locationText
                            : MockIncidentService.instance.locationFor(result),
                      ),
                      const Divider(height: 28),
                      RiskBadge(
                        score: result?.riskScore ?? 96,
                        level: result?.riskLevel ?? RiskLevel.critical,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 8),
                  Flexible(child: Text('Trusted contacts will be notified')),
                ],
              ),
              const SizedBox(height: 28),
              PrimaryActionButton(
                label: 'VIEW TRUSTED CONTACT ALERT',
                onPressed: () {
                  MockIncidentService.instance.updateStatus(
                    IncidentStatus.contactNotified,
                  );
                  Navigator.pushNamed(context, AppRoutes.trustedContactView);
                },
              ),
              const SizedBox(height: 10),
              PrimaryActionButton(
                label: 'VIEW HISTORY',
                outlined: true,
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.history),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
