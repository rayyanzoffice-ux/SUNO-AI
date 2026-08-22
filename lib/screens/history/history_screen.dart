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
  bool cancelled = false;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Incident history')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Alerts'),
                    icon: Icon(Icons.warning_amber),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Cancelled'),
                    icon: Icon(Icons.check_circle_outline),
                  ),
                ],
                selected: {cancelled},
                onSelectionChanged: (value) =>
                    setState(() => cancelled = value.first),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: ListView(
                  children: cancelled
                      ? const [
                          _HistoryCard(
                            title: 'Cancelled alert',
                            event: 'Medium safety check',
                            score: '58%',
                            status: 'User confirmed safe',
                            color: AppColors.safe,
                          ),
                        ]
                      : [
                          _HistoryCard(
                            title: 'Critical alert',
                            event:
                                incident?.detectionResult.eventType ??
                                'Distress Sound + Impact',
                            score:
                                '${incident?.detectionResult.riskScore ?? 96}%',
                            status: currentStatus,
                            color: AppColors.emergency,
                          ),
                          const _HistoryCard(
                            title: 'Medium alert',
                            event: 'Possible distress sound',
                            score: '61%',
                            status: 'Safety check shown',
                            color: AppColors.warning,
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
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.title,
    required this.event,
    required this.score,
    required this.status,
    required this.color,
  });
  final String title, event, score, status;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.shield_outlined, color: color),
          ),
          const SizedBox(width: 14),
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
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
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
                const SizedBox(height: 6),
                Text(event, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 10),
                Text(
                  status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
