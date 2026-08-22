import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/mock_incident_service.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/risk_badge.dart';

class TrustedContactViewScreen extends StatefulWidget {
  const TrustedContactViewScreen({super.key});
  @override
  State<TrustedContactViewScreen> createState() =>
      _TrustedContactViewScreenState();
}

class _TrustedContactViewScreenState extends State<TrustedContactViewScreen> {
  String status = 'Alert received — response needed';
  void update(IncidentStatus incidentStatus, String text) {
    MockIncidentService.instance.updateStatus(incidentStatus, text);
    setState(() => status = text);
  }

  @override
  Widget build(BuildContext context) {
    final result =
        MockIncidentService.instance.currentIncident?.detectionResult;
    final time = result?.detectedAt ?? DateTime.now();
    final displayTime =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted contact alert')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(
                Icons.notification_important_rounded,
                color: AppColors.emergency,
                size: 52,
              ),
              const SizedBox(height: 16),
              const Text(
                'Rayyan may be in danger',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              RiskBadge(
                score: result?.riskScore ?? 96,
                level: result?.riskLevel ?? RiskLevel.critical,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _line(
                        Icons.hearing,
                        'Event',
                        result?.eventType ?? 'Distress Sound + Impact',
                      ),
                      _line(Icons.schedule, 'Time', '$displayTime · Today'),
                      _line(
                        Icons.location_on_outlined,
                        'Location',
                        result == null
                            ? MockIncidentService.locationText
                            : MockIncidentService.instance.locationFor(result),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: AppColors.navyLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 42,
                        color: AppColors.purple,
                      ),
                      SizedBox(height: 8),
                      Text('Map preview unavailable in demo'),
                      Text(
                        'Lahore, Pakistan',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              PrimaryActionButton(
                label: 'THEY ARE SAFE',
                color: AppColors.safe,
                onPressed: () => update(
                  IncidentStatus.resolved,
                  'Resolved — contact confirmed they are safe',
                ),
              ),
              const SizedBox(height: 9),
              PrimaryActionButton(
                label: 'I AM CHECKING ON THEM',
                onPressed: () => update(
                  IncidentStatus.contactChecking,
                  'Contact checking — help is on the way',
                ),
              ),
              const SizedBox(height: 9),
              PrimaryActionButton(
                label: 'UNABLE TO CONTACT',
                color: AppColors.emergency,
                onPressed: () => update(
                  IncidentStatus.alertTriggered,
                  'Escalation needed — unable to contact',
                ),
              ),
              const SizedBox(height: 9),
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

  static Widget _line(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, color: AppColors.purple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
