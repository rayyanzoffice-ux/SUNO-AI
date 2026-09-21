import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/map_preview_card.dart';

class EmergencyAlertScreen extends StatefulWidget {
  const EmergencyAlertScreen({super.key, this.incidentId});
  final String? incidentId;

  @override
  State<EmergencyAlertScreen> createState() => _EmergencyAlertScreenState();
}

class _EmergencyAlertScreenState extends State<EmergencyAlertScreen> {
  late final String? _incidentId;

  @override
  void initState() {
    super.initState();
    _incidentId =
        widget.incidentId ?? SunoRuntimeService.instance.currentIncident?.id;
  }

  String _dispatchSubtitle() {
    final runtime = SunoRuntimeService.instance;
    final incident = _incidentId == null
        ? null
        : runtime.incidentById(_incidentId);
    if (incident?.status == IncidentStatus.cancelled) {
      return 'You confirmed safe. This safety check is closed.';
    }
    if (incident?.status == IncidentStatus.resolved) {
      return 'A contact marked this incident as resolved.';
    }
    if (_incidentId != null && runtime.isDispatching(_incidentId)) {
      return 'Sending alerts to your trusted contacts…';
    }
    final dispatch = incident?.dispatchResult;
    if (dispatch == null) {
      return 'No confirmed delivery result. Check your contacts and retry if needed.';
    }
    if (dispatch.success) {
      return 'FCM accepted ${dispatch.sentCount} of ${dispatch.attemptedCount} alerts. Awaiting a contact response.';
    }
    if (dispatch.partiallyDelivered) {
      return 'FCM accepted ${dispatch.sentCount} of ${dispatch.attemptedCount} alerts. '
          '${dispatch.failedCount} failed.';
    }
    return 'Alert saved locally — contacts could not be reached '
        '(${dispatch.failedReason ?? 'unknown reason'}).';
  }

  static String _levelLabel(RiskLevel level) {
    final w = level.wireValue;
    return '${w[0].toUpperCase()}${w.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: SunoRuntimeService.instance,
          builder: (context, _) {
            final runtime = SunoRuntimeService.instance;
            final incident = _incidentId == null
                ? null
                : runtime.incidentById(_incidentId);
            final result = incident?.detectionResult;
            if (incident == null) {
              return const Center(
                child: Text('This incident is no longer available.'),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 24,
                  ),
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
                                color: AppColors.emergency.withValues(
                                  alpha: .16,
                                ),
                                blurRadius: 30,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: AppColors.emergency,
                            size: 53,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          incident.status == IncidentStatus.resolved
                              ? 'Incident resolved'
                              : incident.status == IncidentStatus.cancelled
                              ? 'Safety check cancelled'
                              : 'Emergency Alert Activated',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.emergency,
                            fontSize: 30,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _dispatchSubtitle(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                        if (incident.contactResponseText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.safe.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                incident.contactResponseText!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.safe,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (result?.isSimulated == true)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'DEMO: simulated danger, real contact notifications',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (incident.status != IncidentStatus.resolved &&
                            incident.status != IncidentStatus.cancelled &&
                            !runtime.isDispatching(incident.id) &&
                            (incident.dispatchResult?.success != true))
                          TextButton(
                            onPressed: () async {
                              try {
                                await runtime.dispatchIncident(incident.id);
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not retry. Please check connectivity.',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: const Text('RETRY ALERT TO ALL CONTACTS'),
                          ),
                        const SizedBox(height: 22),
                        if (result != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 6,
                              ),
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
                                    value:
                                        '${result.riskScore}% '
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
                                    value:
                                        result.locationText ??
                                        'Location unavailable',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (result != null) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Location at alert time',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          MapPreviewCard(
                            latitude: result.latitude,
                            longitude: result.longitude,
                            locationText: result.locationText,
                          ),
                        ],
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
                                'In immediate danger, contact local emergency services.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
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
            );
          },
        ),
      ),
    );
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
          child: Icon(
            icon,
            size: 21,
            color: critical ? AppColors.emergency : AppColors.purple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: critical ? AppColors.emergency : AppColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
