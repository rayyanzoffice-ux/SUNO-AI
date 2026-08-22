import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../services/mock_detection_service.dart';
import '../../services/mock_incident_service.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/status_chip.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});
  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  bool detecting = false;

  Future<void> _simulate() async {
    setState(() => detecting = true);
    final result = await MockDetectionService().simulateCriticalDetection();
    MockIncidentService.instance.createIncident(result);
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.emergencyAlert);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Active monitoring')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    width: 126,
                    height: 126,
                    decoration: BoxDecoration(
                      color: AppColors.safe.withValues(alpha: .13),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.safe, width: 2),
                    ),
                    child: const Icon(
                      Icons.graphic_eq,
                      color: AppColors.safe,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SUNO is Active',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Listening privately on this device',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 30),
                  const StatusChip(
                    label: 'Sound',
                    value: 'Normal',
                    color: AppColors.safe,
                  ),
                  const SizedBox(height: 10),
                  const StatusChip(
                    label: 'Motion',
                    value: 'Stable',
                    color: AppColors.safe,
                  ),
                  const SizedBox(height: 10),
                  const StatusChip(
                    label: 'Connection',
                    value: 'Active',
                    color: AppColors.safe,
                  ),
                  const Spacer(),
                  if (detecting) ...[
                    const StatusChip(
                      label: 'Distress sound detected',
                      value: '93%',
                      color: AppColors.emergency,
                    ),
                    const SizedBox(height: 8),
                    const StatusChip(
                      label: 'Impact detected',
                      value: 'Risk 96% Critical',
                      color: AppColors.emergency,
                    ),
                    const SizedBox(height: 14),
                  ],
                  PrimaryActionButton(
                    label: detecting
                        ? 'ANALYZING CRITICAL RISK…'
                        : 'SIMULATE DISTRESS DETECTION',
                    color: AppColors.emergency,
                    onPressed: detecting ? null : _simulate,
                  ),
                  const SizedBox(height: 10),
                  PrimaryActionButton(
                    label: 'STOP MONITORING',
                    outlined: true,
                    onPressed: detecting
                        ? null
                        : () => Navigator.popUntil(
                            context,
                            ModalRoute.withName(AppRoutes.home),
                          ),
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
