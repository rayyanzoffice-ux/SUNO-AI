import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/map_preview_card.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/risk_badge.dart';

class AlertReceivedScreen extends StatefulWidget {
  const AlertReceivedScreen({super.key, required this.payload});

  final Map<String, String> payload;

  @override
  State<AlertReceivedScreen> createState() => _AlertReceivedScreenState();
}

class _AlertReceivedScreenState extends State<AlertReceivedScreen> {
  final ScrollController _scrollController = ScrollController();
  Incident? get _incident =>
      SunoRuntimeService.instance.incidentById(_incidentId);
  String get _status => _incident == null
      ? 'No response can be sent for this incident.'
      : _incident?.contactResponseText ?? 'Alert received — response needed';
  bool _responding = false;
  bool get _canRespond =>
      !_responding &&
      _incident != null &&
      _incident!.status != IncidentStatus.resolved;

  @override
  void initState() {
    super.initState();
    SunoRuntimeService.instance.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _incidentId => widget.payload['incidentId'] ?? '';
  String get _eventType => widget.payload['eventType'] ?? 'Emergency';
  String get _riskScore => widget.payload['riskScore'] ?? '0';
  String get _riskLevel => widget.payload['riskLevel'] ?? 'critical';
  String get _locationText =>
      widget.payload['locationText'] ?? 'Location unavailable';
  String? get _senderToken => widget.payload['senderToken'];

  double? get _latitude {
    final raw = widget.payload['latitude'];
    return raw == null ? null : double.tryParse(raw);
  }

  double? get _longitude {
    final raw = widget.payload['longitude'];
    return raw == null ? null : double.tryParse(raw);
  }

  DateTime? get _detectedAt {
    final raw = widget.payload['detectedAt'];
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _respond(
    IncidentStatus status,
    String text,
    String statusWire,
    String message,
  ) async {
    if (!_canRespond) return;
    setState(() => _responding = true);
    try {
      final senderToken = _senderToken;
      if (senderToken == null || senderToken.trim().isEmpty) {
        throw StateError(
          'Sender token unavailable. Please contact them directly.',
        );
      }
      await SunoRuntimeService.instance.sendResponse(
        recipientToken: senderToken,
        incidentId: _incidentId,
        responderName: 'Your contact',
        status: statusWire,
        message: message,
      );
      final saved = await SunoRuntimeService.instance.updateStatus(
        status,
        text,
        _incidentId,
      );
      if (saved == null) throw StateError('The incident was removed.');
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Response failed: $e')));
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  void dispose() {
    SunoRuntimeService.instance.removeListener(_refresh);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = _detectedAt?.toLocal();
    final displayTime = time == null
        ? 'Time unavailable'
        : '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} · ${formatClock12Hour(time)}';
    final score = int.tryParse(_riskScore) ?? 0;
    final level = RiskLevel.values.firstWhere(
      (l) => l.wireValue == _riskLevel,
      orElse: () => RiskLevel.critical,
    );

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
                const Center(
                  child: Text(
                    'Your contact',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Center(
                  child: Text(
                    _incident == null
                        ? 'This incident is unavailable'
                        : _incident!.status == IncidentStatus.resolved
                        ? 'Incident resolved'
                        : 'Your contact may be in danger',
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
                  child: RiskBadge(score: score, level: level),
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
                        _line(Icons.hearing_rounded, 'Event', _eventType),
                        const Divider(height: 1),
                        _line(Icons.schedule_rounded, 'Detected', displayTime),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (widget.payload['isSimulated'] == 'true')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('DEMO ALERT — the danger was simulated.'),
                  ),
                const Text(
                  'Location at alert time',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 9),
                MapPreviewCard(
                  latitude: _latitude,
                  longitude: _longitude,
                  locationText: _locationText,
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
                  onPressed: !_canRespond
                      ? null
                      : () => _respond(
                          IncidentStatus.contactChecking,
                          'Contact checking — help is on the way',
                          'contactChecking',
                          'I am checking on them',
                        ),
                ),
                const SizedBox(height: 9),
                PrimaryActionButton(
                  label: 'THEY ARE SAFE',
                  color: AppColors.safe,
                  icon: Icons.check_circle_outline_rounded,
                  onPressed: !_canRespond
                      ? null
                      : () => _respond(
                          IncidentStatus.resolved,
                          'Resolved — contact confirmed they are safe',
                          'resolved',
                          'They are safe',
                        ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: !_canRespond
                        ? null
                        : () => _respond(
                            IncidentStatus.alertTriggered,
                            'Unable to contact — emergency remains active',
                            'alertTriggered',
                            'Unable to contact',
                          ),
                    child: const Text('UNABLE TO CONTACT'),
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
}
