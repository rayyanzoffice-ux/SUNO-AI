import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/incident.dart';
import '../../services/mock_incident_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int filter = 0;
  @override
  Widget build(BuildContext context) {
    final incident = MockIncidentService.instance.currentIncident;
    final currentStatus = switch (incident?.status) {
      IncidentStatus.contactChecking => 'Contact checking',
      IncidentStatus.resolved => 'Resolved — confirmed safe',
      IncidentStatus.cancelled => 'User confirmed safe',
      IncidentStatus.alertTriggered => 'Escalation needed',
      IncidentStatus.contactNotified => 'Contact notified',
      _ => 'Contact checking',
    };
    final alerts = [
      _HistoryCard(
        title: 'Critical alert',
        event: incident?.detectionResult.eventType ?? 'Distress Sound + Impact',
        score: '${incident?.detectionResult.riskScore ?? 96}%',
        status: currentStatus,
        time: 'Today · 10:42',
        color: AppColors.emergency,
      ),
      const _HistoryCard(
        title: 'Safety check',
        event: 'Possible distress sound',
        score: '61%',
        status: 'Safety check shown',
        time: 'Yesterday · 18:20',
        color: AppColors.warning,
      ),
    ];
    const canceled = [
      _HistoryCard(
        title: 'Canceled alert',
        event: 'Medium safety check',
        score: '58%',
        status: 'User confirmed safe',
        time: 'Aug 18 · 21:04',
        color: AppColors.safe,
      ),
    ];
    final cards = filter == 1
        ? alerts
        : filter == 2
        ? canceled
        : [...alerts, ...canceled];
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
                child: ListView.separated(
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 11),
                  itemBuilder: (_, i) => cards[i],
                ),
              ),
            ],
          ),
        ),
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
  });
  final String title, event, score, status, time;
  final Color color;
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
            child: Icon(
              color == AppColors.safe
                  ? Icons.check_rounded
                  : Icons.notifications_active_outlined,
              color: color,
            ),
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
