import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/map_preview_card.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/risk_badge.dart';

class TrustedContactViewScreen extends StatefulWidget {
  const TrustedContactViewScreen({super.key});
  @override
  State<TrustedContactViewScreen> createState() =>
      _TrustedContactViewScreenState();
}

class _TrustedContactViewScreenState extends State<TrustedContactViewScreen> {
  final ScrollController _scrollController = ScrollController();
  String _status = 'Alert received — response needed';
  String _contactName = 'Your contact';

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    final contacts = await SunoRuntimeService.instance.getTrustedContacts();
    if (contacts.isNotEmpty && mounted) {
      setState(() => _contactName = contacts.first.name);
    }
  }

  Future<void> _update(IncidentStatus status, String text) async {
    final runtime = SunoRuntimeService.instance;
    if (runtime.currentIncident != null) {
      await runtime.updateStatus(status, text);
    }
    if (!mounted) return;
    setState(() => _status = text);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = SunoRuntimeService.instance;
    final result = runtime.currentIncident?.detectionResult;
    final received = runtime.receivedAlert;
    final score = result?.riskScore ?? int.tryParse(received?.riskScore ?? '');
    final level = result?.riskLevel ?? _riskLevel(received?.riskLevel);
    final time =
        result?.detectedAt ??
        DateTime.tryParse(received?.detectedAt ?? '') ??
        DateTime.now();
    final displayTime = formatClock12Hour(time);

    return Scaffold(
      appBar: AppBar(title: const Text('Safety alert')),
      body: SafeArea(
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: CircleAvatar(
                    radius: 29,
                    backgroundColor: Color(0xFFFFE8E9),
                    child: Icon(
                      Icons.person_rounded,
                      color: AppColors.emergency,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _contactName,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Center(
                  child: Text(
                    '$_contactName may be in danger',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: RiskBadge(score: score ?? 0, level: level),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: Column(
                      children: [
                        _line(
                          Icons.hearing_rounded,
                          'Event',
                          result?.eventType ?? received?.eventType ?? '—',
                        ),
                        const Divider(height: 1),
                        _line(
                          Icons.schedule_rounded,
                          'Detected',
                          '$displayTime · Today',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Live Location',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 9),
                MapPreviewCard(
                  latitude: result?.latitude,
                  longitude: result?.longitude,
                  locationText: result?.locationText ?? received?.location,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryActionButton(
                  label: 'I AM CHECKING ON THEM',
                  color: AppColors.warning,
                  icon: Icons.directions_run_rounded,
                  onPressed: () => _update(
                    IncidentStatus.contactChecking,
                    'Contact checking — help is on the way',
                  ),
                ),
                const SizedBox(height: 9),
                PrimaryActionButton(
                  label: 'THEY ARE SAFE',
                  color: AppColors.safe,
                  icon: Icons.check_circle_outline_rounded,
                  onPressed: () => _update(
                    IncidentStatus.resolved,
                    'Resolved — contact confirmed they are safe',
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () => _update(
                      IncidentStatus.alertTriggered,
                      'Unable to contact — emergency remains active',
                    ),
                    child: const Text('UNABLE TO CONTACT'),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.history),
                    child: const Text('VIEW HISTORY'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _line(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Icon(icon, color: AppColors.purple, size: 21),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static RiskLevel _riskLevel(String? value) => switch (value) {
    'low' => RiskLevel.low,
    'medium' => RiskLevel.medium,
    _ => RiskLevel.critical,
  };
}
