import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/incident.dart';
import '../../services/suno_runtime_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.runtimeService});

  final SunoRuntimeService? runtimeService;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int filter = 0;

  SunoRuntimeService get _runtimeService =>
      widget.runtimeService ?? SunoRuntimeService.instance;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Incident>>(
    future: _runtimeService.getIncidentHistory(),
    builder: (context, snapshot) =>
        _buildContent(context, snapshot.data ?? const <Incident>[]),
  );

  Widget _buildContent(BuildContext context, List<Incident> incidents) {
    final filteredIncidents = switch (filter) {
      1 => incidents
          .where((incident) => incident.status != IncidentStatus.cancelled)
          .toList(),
      2 => incidents
          .where((incident) => incident.status == IncidentStatus.cancelled)
          .toList(),
      _ => incidents,
    };
    final cards = filteredIncidents.map(_cardFor).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Incident History')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your recent safety activity',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEFF5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: List.generate(3, (i) {
                    final labels = ['All', 'Alerts', 'Canceled'];
                    return Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => filter = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: filter == i
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: filter == i
                                ? const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 5,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            labels[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: filter == i
                                  ? AppColors.text
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '${cards.length} INCIDENTS',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: cards.isEmpty
                    ? Center(
                        child: Text(
                          _emptyStateText(),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: cards.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 11),
                        itemBuilder: (_, i) => cards[i],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _HistoryCard _cardFor(Incident incident) {
    final status = incident.status;
    return _HistoryCard(
      title: _titleFor(status),
      event: incident.detectionResult.eventType,
      score: '${incident.detectionResult.riskScore}%',
      status: _statusFor(status),
      time: _time(incident.createdAt),
      color: _colorFor(status),
      icon: _iconFor(status),
    );
  }

  String _emptyStateText() => switch (filter) {
    1 => 'No alert incidents',
    2 => 'No canceled incidents',
    _ => 'No incidents yet',
  };

  static String _titleFor(IncidentStatus status) => switch (status) {
    IncidentStatus.cancelled => 'Canceled alert',
    IncidentStatus.safetyCheck => 'Safety check',
    IncidentStatus.resolved => 'Resolved alert',
    IncidentStatus.monitoring => 'Monitoring',
    IncidentStatus.alertTriggered ||
    IncidentStatus.contactNotified ||
    IncidentStatus.contactChecking => 'Critical alert',
  };

  static String _statusFor(IncidentStatus status) => switch (status) {
    IncidentStatus.contactChecking => 'Contact checking',
    IncidentStatus.resolved => 'Resolved — confirmed safe',
    IncidentStatus.cancelled => 'User confirmed safe',
    IncidentStatus.alertTriggered => 'Escalation needed',
    IncidentStatus.contactNotified => 'Contact notified',
    IncidentStatus.safetyCheck => 'Safety check shown',
    IncidentStatus.monitoring => 'Monitoring',
  };

  static Color _colorFor(IncidentStatus status) => switch (status) {
    IncidentStatus.cancelled || IncidentStatus.resolved => AppColors.safe,
    IncidentStatus.safetyCheck => AppColors.warning,
    IncidentStatus.monitoring => AppColors.indigo,
    IncidentStatus.alertTriggered ||
    IncidentStatus.contactNotified ||
    IncidentStatus.contactChecking => AppColors.emergency,
  };

  static IconData _iconFor(IncidentStatus status) => switch (status) {
    IncidentStatus.cancelled || IncidentStatus.resolved => Icons.check_rounded,
    IncidentStatus.safetyCheck => Icons.shield_outlined,
    IncidentStatus.monitoring => Icons.hearing_outlined,
    IncidentStatus.alertTriggered ||
    IncidentStatus.contactNotified ||
    IncidentStatus.contactChecking => Icons.notifications_active_outlined,
  };

  static String _time(DateTime time) {
    final now = DateTime.now();
    final eventDate = DateTime(time.year, time.month, time.day);
    final today = DateTime(now.year, now.month, now.day);
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    if (eventDate == today) return 'Today · $clock';
    if (eventDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday · $clock';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[time.month - 1]} ${time.day} · $clock';
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
  });

  final String title, event, score, status, time;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
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
                        style: const TextStyle(fontWeight: FontWeight.w800),
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
  );
}
