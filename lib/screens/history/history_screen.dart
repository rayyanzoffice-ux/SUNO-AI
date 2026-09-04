import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
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

  SunoRuntimeService get _runtime =>
      widget.runtimeService ?? SunoRuntimeService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _runtime.getIncidentHistory();
    if (!mounted) return;
    setState(() {
      _incidents = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filtered = switch (_filter) {
      1 => _incidents
          .where((i) => i.status != IncidentStatus.cancelled)
          .toList(),
      2 => _incidents
          .where((i) => i.status == IncidentStatus.cancelled)
          .toList(),
      _ => _incidents,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Incident History')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your recent safety activity',
                  style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 18),
              _FilterBar(
                  selected: _filter,
                  onSelected: (i) => setState(() => _filter = i)),
              const SizedBox(height: 22),
              Text(
                '${filtered.length} INCIDENTS',
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
                        child: Text(_emptyState(),
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600)))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 11),
                        itemBuilder: (_, i) =>
                            _HistoryCard.from(filtered[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _emptyState() => switch (_filter) {
    1 => 'No alert incidents',
    2 => 'No canceled incidents',
    _ => 'No incidents yet',
  };
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});
  final int selected;
  final void Function(int) onSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFEDEFF5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: List.generate(3, (i) {
        const labels = ['All', 'Alerts', 'Canceled'];
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
                    ? const [
                        BoxShadow(color: Colors.black12, blurRadius: 5)
                      ]
                    : null,
              ),
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected == i
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
  );
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

  factory _HistoryCard.from(Incident incident) {
    final s = incident.status;
    return _HistoryCard(
      title: _titleFor(s),
      event: incident.detectionResult.eventType,
      score: '${incident.detectionResult.riskScore}%',
      status: _statusFor(s),
      time: _time(incident.createdAt),
      color: _colorFor(s),
      icon: _iconFor(s),
    );
  }

  final String title, event, score, status, time;
  final Color color;
  final IconData icon;

  static String _titleFor(IncidentStatus s) => switch (s) {
    IncidentStatus.cancelled => 'Canceled alert',
    IncidentStatus.safetyCheck => 'Safety check',
    IncidentStatus.resolved => 'Resolved alert',
    IncidentStatus.monitoring => 'Monitoring',
    _ => 'Critical alert',
  };

  static String _statusFor(IncidentStatus s) => switch (s) {
    IncidentStatus.contactChecking => 'Contact checking',
    IncidentStatus.resolved => 'Resolved — confirmed safe',
    IncidentStatus.cancelled => 'User confirmed safe',
    IncidentStatus.alertTriggered => 'Escalation needed',
    IncidentStatus.contactNotified => 'Contact notified',
    IncidentStatus.safetyCheck => 'Safety check shown',
    IncidentStatus.monitoring => 'Monitoring',
  };

  static Color _colorFor(IncidentStatus s) => switch (s) {
    IncidentStatus.cancelled || IncidentStatus.resolved => AppColors.safe,
    IncidentStatus.safetyCheck => AppColors.warning,
    IncidentStatus.monitoring => AppColors.indigo,
    _ => AppColors.emergency,
  };

  static IconData _iconFor(IncidentStatus s) => switch (s) {
    IncidentStatus.cancelled || IncidentStatus.resolved =>
      Icons.check_rounded,
    IncidentStatus.safetyCheck => Icons.shield_outlined,
    IncidentStatus.monitoring => Icons.hearing_outlined,
    _ => Icons.notifications_active_outlined,
  };

  static String _time(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final clock = formatClock12Hour(t);
    if (d == today) return 'Today · $clock';
    if (d == today.subtract(const Duration(days: 1))) {
      return 'Yesterday · $clock';
    }
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[t.month - 1]} ${t.day} · $clock';
  }

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
                Row(children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800))),
                  Text(score,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 4),
                Text(event,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMuted)),
                const SizedBox(height: 9),
                Row(children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(status,
                          style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700))),
                  Text(time,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ]),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
