import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/primary_action_button.dart';

class SafetyCheckScreen extends StatefulWidget {
  const SafetyCheckScreen({super.key, this.incidentId});
  final String? incidentId;
  @override
  State<SafetyCheckScreen> createState() => _SafetyCheckScreenState();
}

class _SafetyCheckScreenState extends State<SafetyCheckScreen> {
  static const _totalSeconds = 10;
  int _seconds = _totalSeconds;
  Timer? _timer;
  bool _completed = false;

  late final String? _incidentId;

  @override
  void initState() {
    super.initState();
    _incidentId =
        widget.incidentId ?? SunoRuntimeService.instance.currentIncident?.id;
    SunoRuntimeService.instance.addListener(_refresh);
    _timer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _refresh(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted || _completed) return;
    final incident = _incidentId == null
        ? null
        : SunoRuntimeService.instance.incidentById(_incidentId);
    if (incident == null || incident.status != IncidentStatus.safetyCheck) {
      _completed = true;
      _timer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          incident == null
              ? AppRoutes.home
              : incident.status == IncidentStatus.cancelled
              ? AppRoutes.monitoring
              : AppRoutes.emergencyAlert,
          arguments: incident?.id,
        );
      });
      return;
    }
    final deadline =
        incident.safetyCheckDeadline ??
        incident.createdAt.add(const Duration(seconds: 10));
    setState(
      () =>
          _seconds = (deadline.difference(DateTime.now()).inMilliseconds / 1000)
              .ceil()
              .clamp(0, _totalSeconds)
              .toInt(),
    );
  }

  void _emergency() {
    if (!_completed && _incidentId != null) {
      SunoRuntimeService.instance.escalateSafetyCheck(_incidentId);
    }
  }

  void _safe() {
    if (!_completed && _incidentId != null) {
      SunoRuntimeService.instance.confirmSafe(_incidentId);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    SunoRuntimeService.instance.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: .1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 54,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Possible emergency\ndetected',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.2,
                      color: AppColors.emergency,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Are you safe?',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
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
                            value: _seconds / _totalSeconds,
                            strokeWidth: 9,
                            color: AppColors.warning,
                            backgroundColor: AppColors.border,
                          ),
                        ),
                        Text(
                          '$_seconds',
                          style: const TextStyle(
                            fontSize: 44,
                            color: AppColors.text,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    SunoRuntimeService.instance.safetyCheckNeedsRetry
                        ? SunoRuntimeService.instance.operationError!
                        : 'Alert activates automatically when time runs out',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SunoRuntimeService.instance.safetyCheckNeedsRetry
                          ? AppColors.emergency
                          : AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  PrimaryActionButton(
                    label: SunoRuntimeService.instance.safetyCheckNeedsRetry
                        ? 'RETRY: I AM SAFE'
                        : 'I AM SAFE',
                    color: AppColors.safe,
                    onPressed: _safe,
                  ),
                  const SizedBox(height: 12),
                  PrimaryActionButton(
                    label: SunoRuntimeService.instance.safetyCheckNeedsRetry
                        ? 'RETRY EMERGENCY ALERT'
                        : "CAN'T RESPOND",
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
