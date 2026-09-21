import 'package:flutter/material.dart';

import '../../backend/location/location_service.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/monitoring_service.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/map_preview_card.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/silent_sos_sheet.dart';
import '../../widgets/status_chip.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({
    super.key,
    this.scenario = DetectionScenario.critical,
    this.runtime,
  });
  final DetectionScenario scenario;
  final SunoRuntimeService? runtime;
  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  late DetectionScenario selectedScenario;
  late final SunoRuntimeService _runtime;
  late final MonitoringService _monitoring;
  bool detecting = false;
  bool _navigating = false;
  String? _message;
  String? _previousIncident;

  @override
  void initState() {
    super.initState();
    _runtime = widget.runtime ?? SunoRuntimeService.instance;
    _monitoring = widget.runtime == null
        ? MonitoringService.instance
        : MonitoringService(_runtime);
    selectedScenario = widget.scenario;
    _previousIncident = _runtime.currentIncident?.id;
    _runtime.addListener(_onRuntimeChanged);
    _monitoring.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runtime.refreshLocation();
      if (_runtime.hasPendingSafetyCheck) {
        _openIncident(_runtime.currentIncident!);
      }
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    _rebuild();
    final incident = _runtime.currentIncident;
    if (incident != null && incident.id != _previousIncident) {
      _previousIncident = incident.id;
      if (!detecting) _openIncident(incident);
    }
  }

  void _openIncident(Incident incident) {
    if (_navigating || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        incident.status == IncidentStatus.safetyCheck
            ? AppRoutes.safetyCheck
            : AppRoutes.emergencyAlert,
        arguments: incident.id,
      );
    });
  }

  Future<void> _simulate() async {
    if (detecting) return;
    setState(() {
      detecting = true;
      _message = null;
    });
    try {
      final result = await _runtime.runDetection(selectedScenario);
      if (!mounted) return;
      if (result.riskLevel == RiskLevel.low) {
        setState(
          () => _message = 'Low-risk simulation complete. No alert was sent.',
        );
      } else {
        final incident = await _runtime.recordDetection(result);
        if (mounted && incident != null) _openIncident(incident);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Simulation could not finish. Please retry.');
      }
    } finally {
      if (mounted) setState(() => detecting = false);
    }
  }

  @override
  void dispose() {
    _runtime.removeListener(_onRuntimeChanged);
    _monitoring.removeListener(_rebuild);
    if (widget.runtime != null) _monitoring.dispose();
    super.dispose();
  }

  String get _locationStatus => _runtime.locating
      ? 'Locating…'
      : switch (_runtime.locationService.status) {
          LocationStatus.ready => 'GPS ready',
          LocationStatus.denied => 'Permission denied',
          LocationStatus.disabled => 'GPS disabled',
          LocationStatus.timedOut => 'GPS timed out — retry',
          _ => 'Unavailable',
        };

  @override
  Widget build(BuildContext context) {
    final live = _monitoring.liveMode;
    final busy = detecting || _monitoring.starting;
    return Scaffold(
      appBar: AppBar(title: const Text('Monitoring')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Demo Mode'),
                      selected: !live,
                      onSelected: busy ? null : (_) => _monitoring.selectDemo(),
                    ),
                  ),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(
                        _monitoring.starting ? 'Starting…' : 'Live Mode',
                      ),
                      selected: live,
                      onSelected: busy ? null : (_) => _monitoring.start(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onLongPress: () => showSilentSosSheet(context),
                child: CircleAvatar(
                  radius: 58,
                  backgroundColor: AppColors.safe.withValues(alpha: .1),
                  child: Icon(
                    live ? Icons.mic_rounded : Icons.science_outlined,
                    size: 56,
                    color: AppColors.safe,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                live
                    ? (_monitoring.active
                          ? 'SUNO is Listening Live'
                          : 'Live monitoring paused')
                    : 'Demo Mode',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.safe,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                live ? 'Audio is processed only on this device.' : 'Simulated danger • Real GPS and contact alerts\nThe microphone is off in Demo mode.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              const Text(
                'Long-press the icon for Silent SOS',
                style: TextStyle(fontSize: 11),
              ),
              if (_monitoring.error != null ||
                  _runtime.operationError != null ||
                  _message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _message ?? _monitoring.error ?? _runtime.operationError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.warning),
                  ),
                ),
              if (live && _monitoring.active)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: SizedBox(
                    height: 38,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(23, (index) {
                        final offset = 23 - _monitoring.levels.length;
                        final amplitude = index < offset
                            ? 0.0
                            : _monitoring.levels[index - offset];
                        return Container(
                          width: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 6 + amplitude.clamp(0, 1) * 32,
                          color: AppColors.safe,
                        );
                      }),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (!live)
                Wrap(
                  spacing: 8,
                  children: DetectionScenario.values
                      .map(
                        (scenario) => ChoiceChip(
                          label: Text(scenario.name.toUpperCase()),
                          selected: selectedScenario == scenario,
                          onSelected: busy
                              ? null
                              : (_) =>
                                    setState(() => selectedScenario = scenario),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: StatusChip(
                      label: 'Sound',
                      value: live && _monitoring.active
                          ? 'Listening'
                          : 'Mic off',
                      color: AppColors.safe,
                      icon: Icons.graphic_eq,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatusChip(
                      label: 'Location',
                      value: _locationStatus,
                      color: _runtime.location == null
                          ? AppColors.warning
                          : AppColors.safe,
                      icon: Icons.location_on,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Current location',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: busy || _runtime.locating
                        ? null
                        : () => _runtime.refreshLocation(),
                    child: const Text('Refresh GPS'),
                  ),
                ],
              ),
              MapPreviewCard(
                latitude: _runtime.location?.latitude,
                longitude: _runtime.location?.longitude,
                locationText: _runtime.location?.description ?? _locationStatus,
              ),
              const SizedBox(height: 16),
              if (!live)
                OutlinedButton.icon(
                  onPressed: busy ? null : _simulate,
                  icon: const Icon(Icons.science_outlined),
                  label: Text(
                    detecting
                        ? 'Preparing simulation…'
                        : 'Demo: Simulate Distress',
                  ),
                ),
              if (live && !_monitoring.active)
                PrimaryActionButton(
                  label: 'START LIVE MONITORING',
                  onPressed: busy ? null : _monitoring.start,
                ),
              const SizedBox(height: 10),
              PrimaryActionButton(
                label: 'STOP MONITORING',
                outlined: true,
                color: AppColors.emergency,
                onPressed: detecting
                    ? null
                    : () async {
                        await _monitoring.stop();
                        if (!context.mounted) return;
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
