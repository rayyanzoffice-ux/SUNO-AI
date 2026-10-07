import 'package:flutter/material.dart';

import '../../core/l10n/event_type_labels.dart';
import '../../core/l10n/l10n.dart';
import '../../core/navigation/alert_navigation.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/suno_runtime_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.runtimeService});
  final SunoRuntimeService? runtimeService;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _filter = 0;
  List<Incident> _incidents = const [];
  bool _loading = true;
  bool _clearing = false;
  bool _loadFailed = false;

  SunoRuntimeService get _runtime =>
      widget.runtimeService ?? SunoRuntimeService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _runtime.getIncidentHistory();
      if (mounted) {
        setState(() {
          _incidents = data;
          _loadFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _remove(String id) async {
    try {
      await _runtime.removeIncident(id);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.historyDeleteFailed)),
        );
      }
      return false;
    }
  }

  Future<void> _clearAll() async {
    if (_clearing) return;
    final l10n = context.l10n;
    setState(() => _clearing = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.historyClearDialogTitle),
          content: Text(l10n.historyClearDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.historyClearDialogConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _runtime.clearIncidentHistory();
      if (!mounted) return;
      setState(() => _incidents = []);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.historyClearFailed)),
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  /// Opens the detail screen for a critical incident. Does nothing for others.
  void _openIncident(Incident incident) {
    if (incident.detectionResult.riskLevel != RiskLevel.critical) return;
    if (incident.isReceived) {
      Navigator.pushNamed(
        context,
        AppRoutes.alertReceived,
        arguments: alertReceivedArguments(incident),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      incident.status == IncidentStatus.safetyCheck
          ? AppRoutes.safetyCheck
          : AppRoutes.emergencyAlert,
      arguments: incident.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final l10n = context.l10n;
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final filtered = switch (_filter) {
      1 =>
        _incidents.where((i) => i.status != IncidentStatus.cancelled).toList(),
      2 =>
        _incidents.where((i) => i.status == IncidentStatus.cancelled).toList(),
      _ => _incidents,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          if (_incidents.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.historyClearAllTooltip,
              onPressed: _clearing ? null : _clearAll,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.historySubtitle,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (_loadFailed) ...[
                Text(
                  l10n.historyLoadFailed,
                  style: const TextStyle(color: AppColors.emergency),
                ),
                TextButton(
                  onPressed: _load,
                  child: Text(l10n.commonRetry),
                ),
              ],
              const SizedBox(height: 18),
              _FilterBar(
                selected: _filter,
                onSelected: (i) => setState(() => _filter = i),
              ),
              const SizedBox(height: 22),
              Text(
                l10n.historyIncidentCount(filtered.length),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _emptyState(l10n),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 11),
                        itemBuilder: (_, i) => Dismissible(
                          key: ValueKey(filtered[i].id),
                          direction:
                              _clearing ||
                                  _runtime.isDispatching(filtered[i].id) ||
                                  filtered[i].status ==
                                      IncidentStatus.safetyCheck
                              ? DismissDirection.none
                              : DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerEnd,
                            padding: const EdgeInsetsDirectional.only(end: 20),
                            decoration: BoxDecoration(
                              color: AppColors.emergency,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (_) => _remove(filtered[i].id),
                          onDismissed: (_) => setState(() {
                            final id = filtered[i].id;
                            _incidents = _incidents
                                .where((incident) => incident.id != id)
                                .toList();
                          }),
                          child: _HistoryCard.from(
                            filtered[i],
                            l10n,
                            localeName,
                            onTap: filtered[i].detectionResult.riskLevel ==
                                    RiskLevel.critical
                                ? () => _openIncident(filtered[i])
                                : null,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _emptyState(AppLocalizations l10n) => switch (_filter) {
    1 => l10n.historyEmptyAlerts,
    2 => l10n.historyEmptyCanceled,
    _ => l10n.historyEmptyAll,
  };
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});
  final int selected;
  final void Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.historyFilterAll,
      l10n.historyFilterAlerts,
      l10n.historyFilterCanceled,
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(3, (i) {
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected == i ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: selected == i
                      ? const [BoxShadow(color: Colors.black12, blurRadius: 5)]
                      : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected == i ? AppColors.text : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.title,
    required this.event,
    required this.score,
    required this.status,
    required this.time,
    required this.color,
    required this.icon,
    required this.id,
    this.originLabel,
    this.onTap,
  });

  factory _HistoryCard.from(
    Incident incident,
    AppLocalizations l10n,
    String localeName, {
    VoidCallback? onTap,
  }) {
    final s = incident.status;
    return _HistoryCard(
      id: incident.id,
      title: _titleFor(s, incident.isReceived, l10n),
      event: localizedEventType(l10n, incident.detectionResult.eventType),
      score: '${incident.detectionResult.riskScore}%',
      status: _statusFor(s, l10n),
      time: _time(incident.createdAt, l10n, localeName),
      color: _colorFor(s),
      icon: _iconFor(s, incident.isReceived),
      originLabel: incident.isReceived
          ? l10n.historyFrom(incident.origin)
          : null,
      onTap: onTap,
    );
  }

  final String id;
  final String title, event, score, status, time;
  final Color color;
  final IconData icon;
  final String? originLabel;
  final VoidCallback? onTap;

  static String _titleFor(
    IncidentStatus s,
    bool isReceived,
    AppLocalizations l10n,
  ) {
    if (isReceived) return l10n.historyCardReceivedAlert;
    return switch (s) {
      IncidentStatus.cancelled => l10n.historyCardCanceledAlert,
      IncidentStatus.safetyCheck => l10n.historyCardSafetyCheck,
      IncidentStatus.resolved => l10n.historyCardResolvedAlert,
      IncidentStatus.monitoring => l10n.historyCardMonitoring,
      _ => l10n.historyCardCriticalAlert,
    };
  }

  static String _statusFor(IncidentStatus s, AppLocalizations l10n) =>
      switch (s) {
        IncidentStatus.contactChecking => l10n.historyStatusContactChecking,
        IncidentStatus.resolved => l10n.historyStatusResolved,
        IncidentStatus.cancelled => l10n.historyStatusUserSafe,
        IncidentStatus.alertTriggered => l10n.historyStatusEscalationNeeded,
        IncidentStatus.contactNotified => l10n.historyStatusFcmAccepted,
        IncidentStatus.safetyCheck => l10n.historyStatusSafetyPending,
        IncidentStatus.monitoring => l10n.historyStatusMonitoring,
      };

  static Color _colorFor(IncidentStatus s) => switch (s) {
    IncidentStatus.cancelled || IncidentStatus.resolved => AppColors.safe,
    IncidentStatus.safetyCheck => AppColors.warning,
    IncidentStatus.monitoring => AppColors.indigo,
    _ => AppColors.emergency,
  };

  static IconData _iconFor(IncidentStatus s, bool isReceived) {
    if (isReceived) return Icons.download_rounded;
    return switch (s) {
      IncidentStatus.cancelled ||
      IncidentStatus.resolved => Icons.check_rounded,
      IncidentStatus.safetyCheck => Icons.shield_outlined,
      IncidentStatus.monitoring => Icons.hearing_outlined,
      _ => Icons.notifications_active_outlined,
    };
  }

  static String _time(
    DateTime t,
    AppLocalizations l10n,
    String localeName,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final clock = formatClockLocalized(t, localeName);
    if (d == today) return l10n.historyTodayAt(clock);
    if (d == today.subtract(const Duration(days: 1))) {
      return l10n.historyYesterdayAt(clock);
    }
    return l10n.historyDateAt(formatMonthDayLocalized(t, localeName), clock);
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        score,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  if (originLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      originLabel!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.indigo,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    event,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
