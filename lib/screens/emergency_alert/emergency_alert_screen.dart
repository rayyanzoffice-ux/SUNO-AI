import 'package:flutter/material.dart';

import '../../core/l10n/event_type_labels.dart';
import '../../core/l10n/l10n.dart';
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

  String _dispatchSubtitle(AppLocalizations l10n) {
    final runtime = SunoRuntimeService.instance;
    final incident = _incidentId == null
        ? null
        : runtime.incidentById(_incidentId);
    if (incident?.status == IncidentStatus.cancelled) {
      return l10n.emergencyClosedSafe;
    }
    if (incident?.status == IncidentStatus.resolved) {
      return l10n.emergencyContactResolved;
    }
    if (_incidentId != null && runtime.isDispatching(_incidentId)) {
      return l10n.emergencySending;
    }
    final dispatch = incident?.dispatchResult;
    if (dispatch == null) {
      return l10n.emergencyNoDeliveryResult;
    }
    if (dispatch.success) {
      return l10n.emergencyDispatchAwaiting(
        dispatch.sentCount,
        dispatch.attemptedCount,
      );
    }
    if (dispatch.partiallyDelivered) {
      return l10n.emergencyDispatchPartial(
        dispatch.sentCount,
        dispatch.attemptedCount,
        dispatch.failedCount,
      );
    }
    return l10n.emergencySavedLocally(
      dispatch.failedReason ?? l10n.emergencyUnknownReason,
    );
  }

  /// Stored, not looked up: translate only the two tokens this app writes, and
  /// pass through any text a trusted contact typed themselves.
  static String _responseText(AppLocalizations l10n, String raw) =>
      switch (raw) {
        'User confirmed safe' => l10n.historyStatusUserSafe,
        'Safety check escalated' => l10n.statusSafetyCheckEscalated,
        _ => raw,
      };

  static String _levelLabel(AppLocalizations l10n, RiskLevel level) =>
      switch (level) {
        RiskLevel.low => l10n.riskLevelLow,
        RiskLevel.medium => l10n.riskLevelMedium,
        RiskLevel.critical => l10n.riskLevelCritical,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: SunoRuntimeService.instance,
          builder: (context, _) {
            final l10n = context.l10n;
            final runtime = SunoRuntimeService.instance;
            final incident = _incidentId == null
                ? null
                : runtime.incidentById(_incidentId);
            final result = incident?.detectionResult;
            if (incident == null) {
              return Center(child: Text(l10n.errorIncidentUnavailable));
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
                              ? l10n.emergencyIncidentResolved
                              : incident.status == IncidentStatus.cancelled
                              ? l10n.emergencyCheckCancelled
                              : l10n.emergencyAlertActivated,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.emergency,
                            fontSize: 30,
                            height: 1.4,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _dispatchSubtitle(l10n),
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
                                _responseText(
                                  l10n,
                                  incident.contactResponseText!,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.safe,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (result?.isSimulated == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              l10n.emergencyDemoNote,
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
                                  SnackBar(
                                    content: Text(l10n.emergencyRetryFailed),
                                  ),
                                );
                              }
                            },
                            child: Text(l10n.emergencyRetryButton),
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
                                    label: l10n.emergencyLabelEvent,
                                    value: localizedEventType(
                                      l10n,
                                      result.eventType,
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  _Detail(
                                    icon: Icons.speed_rounded,
                                    label: l10n.emergencyLabelRiskScore,
                                    value: l10n.emergencyRiskValue(
                                      result.riskScore,
                                      _levelLabel(l10n, result.riskLevel),
                                    ),
                                    critical: true,
                                  ),
                                  const Divider(height: 1),
                                  _Detail(
                                    icon: Icons.analytics_outlined,
                                    label: l10n.emergencyLabelConfidence,
                                    value:
                                        '${(result.confidence * 100).round()}%',
                                  ),
                                  const Divider(height: 1),
                                  _Detail(
                                    icon: Icons.location_on_outlined,
                                    label: l10n.commonLocation,
                                    value:
                                        result.locationText ??
                                        l10n.commonLocationUnavailable,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (result != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            l10n.emergencyLocationAtAlert,
                            style: const TextStyle(
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
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 7,
                            runSpacing: 4,
                            children: [
                              const Icon(
                                Icons.verified_user_outlined,
                                color: AppColors.safe,
                                size: 18,
                              ),
                              Text(
                                l10n.emergencyLocalServicesNote,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
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
                          child: Text(l10n.emergencyViewHistory),
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
