import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/primary_action_button.dart';

class EmergencyAlertScreen extends StatelessWidget {
  const EmergencyAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final incident = SunoRuntimeService.instance.currentIncident;
    final result = incident?.detectionResult;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 24),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.emergency.withValues(alpha: .1),
                        border: Border.all(
                          color: AppColors.emergency.withValues(alpha: .22),
                          width: 7,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emergency.withValues(alpha: .16),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.notifications_active_rounded,
                          color: AppColors.emergency, size: 53),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Emergency Alert Activated',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.emergency,
                        fontSize: 30,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your trusted contacts are being notified.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 22),
                    if (result != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 6),
                          child: Column(
                            children: [
                              _Detail(
                                icon: Icons.hearing_rounded,
                                label: 'Event',
                                value: result.eventType,
                              ),
                              const Divider(height: 1),
                              _Detail(
                                icon: Icons.speed_rounded,
                                label: 'Risk Score',
                                value: '${result.riskScore}% '
                                    '(${_levelLabel(result.riskLevel)})',
                                critical: true,
                              ),
                              const Divider(height: 1),
                              _Detail(
                                icon: Icons.analytics_outlined,
                                label: 'Confidence',
                                value:
                                    '${(result.confidence * 100).round()}%',
                              ),
                              const Divider(height: 1),
                              _Detail(
                                icon: Icons.location_on_outlined,
                                label: 'Location',
                                value: result.locationText ??
                                    'Location unavailable',
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 7,
                        runSpacing: 4,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: AppColors.safe,
                            size: 18,
                          ),
                          Text(
                            'Safety network activated',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    PrimaryActionButton(
                      label: 'VIEW LOCATION',
                      color: AppColors.emergency,
                      icon: Icons.location_on_rounded,
                      onPressed: () async {
                        await SunoRuntimeService.instance
                            .updateStatus(IncidentStatus.contactNotified);
                        if (context.mounted) {
                          Navigator.pushNamed(
                              context, AppRoutes.trustedContactView);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.history),
                      child: const Text('View incident history'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _levelLabel(RiskLevel level) {
    final w = level.wireValue;
    return '${w[0].toUpperCase()}${w.substring(1)}';
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.icon,
    required this.label,
    required this.value,
    this.critical = false,
  });
  final IconData icon;
  final String label, value;
  final bool critical;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: (critical ? AppColors.emergency : AppColors.purple)
                .withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 21,
              color: critical ? AppColors.emergency : AppColors.purple),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                    color: critical ? AppColors.emergency : AppColors.text,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
        ),
      ],
    ),
  );
}
