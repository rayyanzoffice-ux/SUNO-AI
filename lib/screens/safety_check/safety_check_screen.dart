import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/incident.dart';
import '../../services/mock_detection_service.dart';
import '../../services/mock_incident_service.dart';
import '../../widgets/primary_action_button.dart';

class SafetyCheckScreen extends StatefulWidget {
  const SafetyCheckScreen({super.key});
  @override
  State<SafetyCheckScreen> createState() => _SafetyCheckScreenState();
}

class _SafetyCheckScreenState extends State<SafetyCheckScreen> {
  int seconds = 10;
  Timer? timer;
  bool completed = false;
  @override
  void initState() {
    super.initState();
    if (MockIncidentService.instance.currentIncident == null) {
      MockIncidentService.instance.createIncident(
        MockDetectionService().createCriticalDemoResult(),
      );
    }
    MockIncidentService.instance.updateStatus(IncidentStatus.safetyCheck);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (seconds <= 1) {
        timer?.cancel();
        _emergency();
      } else {
        setState(() => seconds--);
      }
    });
  }

  void _emergency() {
    if (completed) return;
    completed = true;
    timer?.cancel();
    MockIncidentService.instance.updateStatus(
      IncidentStatus.alertTriggered,
      'No response received',
    );
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.emergencyAlert);
    }
  }

  void _safe() {
    if (completed) return;
    completed = true;
    timer?.cancel();
    MockIncidentService.instance.updateStatus(
      IncidentStatus.cancelled,
      'User confirmed safe',
    );
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.history);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const Spacer(),
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 74,
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Possible emergency detected',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Are you safe?',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 34),
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: seconds / 10,
                            strokeWidth: 8,
                            color: AppColors.warning,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        Text(
                          '$seconds',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Alert activates automatically when time runs out',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  PrimaryActionButton(
                    label: 'I AM SAFE',
                    color: AppColors.safe,
                    onPressed: _safe,
                  ),
                  const SizedBox(height: 12),
                  PrimaryActionButton(
                    label: "CAN'T RESPOND",
                    color: AppColors.emergency,
                    onPressed: _emergency,
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
