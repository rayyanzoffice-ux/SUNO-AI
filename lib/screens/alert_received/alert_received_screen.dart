import 'package:flutter/material.dart';

import '../../core/l10n/event_type_labels.dart';
import '../../core/l10n/l10n.dart';
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

  /// Incident id of the alert screen currently on screen, or null. Lets the
  /// notification router avoid pushing a second copy of the same alert.
  static final ValueNotifier<String?> visibleIncidentId =
      ValueNotifier<String?>(null);

  @override
  State<AlertReceivedScreen> createState() => _AlertReceivedScreenState();
}

class _AlertReceivedScreenState extends State<AlertReceivedScreen> {
  final ScrollController _scrollController = ScrollController();
  Incident? get _incident =>
      SunoRuntimeService.instance.incidentById(_incidentId);

  /// The responder's own status line, kept on this device in the responder's
  /// language. What is sent to the person in danger is written in *their*
  /// language instead, because they are the one who has to read it.
  String _statusText(AppLocalizations l10n) => _incident == null
      ? l10n.receivedNoResponse
      : _incident?.contactResponseText ?? l10n.receivedResponseNeeded;
  bool _responding = false;
  bool get _canRespond =>
      !_responding &&
      _incident != null &&
      _incident!.status != IncidentStatus.resolved;

  @override
  void initState() {
    super.initState();
    AlertReceivedScreen.visibleIncidentId.value = _incidentId;
    SunoRuntimeService.instance.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _incidentId => widget.payload['incidentId'] ?? '';
  String get _eventType => widget.payload['eventType'] ?? 'Emergency';
  String get _riskScore => widget.payload['riskScore'] ?? '0';
  String get _riskLevel => widget.payload['riskLevel'] ?? 'critical';
  String? get _locationText => widget.payload['locationText'];
  String? get _senderToken => widget.payload['senderToken'];

  /// Language of the person in danger, as carried by the alert. The stored
  /// incident already normalises it; the payload keys cover a live notification
  /// whose incident row has not been read back yet.
  String? get _senderLang =>
      _incident?.senderLang ??
      widget.payload['lang'] ??
      widget.payload['languageCode'];

  /// Strings for text **sent to** the person in danger, so their reply banner
  /// and the text inside it read in their language, not in this reader's.
  AppLocalizations get _senderL10n => appLocalizationsFor(_senderLang);

  /// Best available name for the person in danger, or null when unknown.
  String? get _senderName {
    final saved = _incident?.senderName?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    final fromPayload = widget.payload['senderName']?.trim();
    return (fromPayload == null || fromPayload.isEmpty) ? null : fromPayload;
  }

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
    final l10n = context.l10n;
    setState(() => _responding = true);
    try {
      final senderToken = _senderToken;
      if (senderToken == null || senderToken.trim().isEmpty) {
        throw StateError(l10n.receivedSenderTokenMissing);
      }
      String? myName;
      try {
        myName = await SunoRuntimeService.instance.getMyName();
      } catch (error) {
        debugPrint('SUNO could not read display name: $error');
      }
      await SunoRuntimeService.instance.sendResponse(
        recipientToken: senderToken,
        incidentId: _incidentId,
        responderName: myName ?? _senderL10n.receivedYourContact,
        status: statusWire,
        message: message,
        recipientLang: _senderLang,
      );
      final saved = await SunoRuntimeService.instance.updateStatus(
        status,
        text,
        _incidentId,
      );
      if (saved == null) throw StateError(l10n.receivedIncidentRemoved);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.receivedResponseFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  void dispose() {
    if (AlertReceivedScreen.visibleIncidentId.value == _incidentId) {
      AlertReceivedScreen.visibleIncidentId.value = null;
    }
    SunoRuntimeService.instance.removeListener(_refresh);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final time = _detectedAt?.toLocal();
    final displayTime = time == null
        ? l10n.receivedTimeUnavailable
        : '${formatIsoDay(time)} · ${formatClock12Hour(time)}';
    final score = int.tryParse(_riskScore) ?? 0;
    final level = RiskLevel.values.firstWhere(
      (l) => l.wireValue == _riskLevel,
      orElse: () => RiskLevel.critical,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.receivedTitle)),
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
                    l10n.receivedYourContact,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Center(
                  child: Text(
                    _incident == null
                        ? l10n.receivedIncidentUnavailable
                        : _incident!.status == IncidentStatus.resolved
                        ? l10n.receivedIncidentResolved
                        : l10n.receivedMayBeInDanger(
                            _senderName ?? l10n.receivedYourContact,
                          ),
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
                        _line(
                          Icons.hearing_rounded,
                          l10n.receivedEventLabel,
                          localizedEventType(l10n, _eventType),
                        ),
                        const Divider(height: 1),
                        _line(
                          Icons.schedule_rounded,
                          l10n.receivedDetectedLabel,
                          displayTime,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (widget.payload['isSimulated'] == 'true')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(l10n.receivedDemoNotice),
                  ),
                Text(
                  l10n.receivedLocationHeading,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                MapPreviewCard(
                  latitude: _latitude,
                  longitude: _longitude,
                  locationText: _locationText ?? l10n.commonLocationUnavailable,
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
                    _statusText(l10n),
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
                  label: l10n.receivedButtonChecking,
                  color: AppColors.warning,
                  icon: Icons.directions_run_rounded,
                  onPressed: !_canRespond
                      ? null
                      : () => _respond(
                          IncidentStatus.contactChecking,
                          l10n.receivedStatusChecking,
                          'contactChecking',
                          _senderL10n.receivedMessageChecking,
                        ),
                ),
                const SizedBox(height: 9),
                PrimaryActionButton(
                  label: l10n.receivedButtonSafe,
                  color: AppColors.safe,
                  icon: Icons.check_circle_outline_rounded,
                  onPressed: !_canRespond
                      ? null
                      : () => _respond(
                          IncidentStatus.resolved,
                          l10n.receivedStatusResolved,
                          'resolved',
                          _senderL10n.receivedMessageSafe,
                        ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: !_canRespond
                        ? null
                        : () => _respond(
                            IncidentStatus.alertTriggered,
                            l10n.receivedStatusUnable,
                            'alertTriggered',
                            _senderL10n.receivedMessageUnable,
                          ),
                    child: Text(l10n.receivedButtonUnable),
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
