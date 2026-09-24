import 'package:flutter/material.dart';

import '../../backend/location/location_service.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../../services/monitoring_service.dart';
import '../../services/suno_runtime_service.dart';
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
    final liveError = _monitoring.error ?? _runtime.operationError;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 20,
              color: AppColors.safe,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 26),
              child: IntrinsicHeight(
                child: Column(
            children: [
              const SizedBox(height: 4),
              _ModeToggle(
                liveMode: live,
                liveStarting: _monitoring.starting,
                onDemoSelected: live && !busy ? _monitoring.selectDemo : null,
                onLiveSelected: !live && !busy ? _monitoring.start : null,
              ),
              if (live && (liveError != null || _monitoring.motionWarning != null)) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.emergency.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    liveError ?? _monitoring.motionWarning!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.emergency,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              GestureDetector(
                onLongPress: () => showSilentSosSheet(context),
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.safe.withValues(alpha: .09),
                    border: Border.all(
                      color: AppColors.safe.withValues(alpha: .25),
                      width: 8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.safe.withValues(alpha: .18),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: Icon(
                    live ? Icons.mic_rounded : Icons.science_outlined,
                    color: AppColors.safe,
                    size: 58,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                live
                    ? (_monitoring.active
                          ? 'SUNO is Listening Live'
                          : 'Live monitoring paused')
                    : 'SUNO is Active',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  color: AppColors.safe,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                live
                    ? 'Real microphone and location — processed on this device'
                    : 'Simulated danger • Real GPS and contact alerts\nThe microphone is off in Demo mode.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              const Text(
                'Long-press the mic for Silent SOS',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              _Waveform(levels: live ? _monitoring.levels : null),
              const SizedBox(height: 24),
              if (!live)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: DetectionScenario.values
                      .map(
                        (scenario) => ChoiceChip(
                          label: Text(_scenarioLabel(scenario)),
                          selected: selectedScenario == scenario,
                          onSelected: busy
                              ? null
                              : (_) =>
                                    setState(() => selectedScenario = scenario),
                          selectedColor: AppColors.purple.withValues(alpha: .14),
                          checkmarkColor: AppColors.purple,
                          labelStyle: TextStyle(
                            color: selectedScenario == scenario
                                ? AppColors.purple
                                : AppColors.text,
                            fontWeight: FontWeight.w800,
                          ),
                          side: BorderSide(
                            color: selectedScenario == scenario
                                ? AppColors.purple
                                : AppColors.border,
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (!live) const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: StatusChip(
                      label: 'Sound',
                      value: live && _monitoring.active
                          ? 'Listening'
                          : live
                          ? 'Starting…'
                          : 'Normal',
                      color: AppColors.safe,
                      icon: Icons.graphic_eq_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatusChip(
                      label: 'Motion',
                      value: live
                          ? (_monitoring.motionWarning == null
                                ? 'Sensing'
                                : 'Unavailable')
                          : 'Stable',
                      color: _monitoring.motionWarning == null
                          ? AppColors.safe
                          : AppColors.warning,
                      icon: Icons.screen_rotation_alt_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatusChip(
                      label: 'Location',
                      value: live ? _locationStatus : 'Demo',
                      color: _runtime.location == null
                          ? AppColors.warning
                          : AppColors.safe,
                      icon: Icons.wifi_rounded,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (detecting)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Analyzing ${_scenarioLabel(selectedScenario).toLowerCase()} risk…',
                    style: const TextStyle(
                      color: AppColors.emergency,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (!live)
                OutlinedButton.icon(
                  onPressed: busy ? null : _simulate,
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: Text(
                    detecting
                        ? 'Analyzing…'
                        : 'Demo: Simulate Distress',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
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
                icon: Icons.stop_circle_outlined,
                onPressed: detecting
                    ? null
                    : () async {
                        await _monitoring.stop();
                        if (!context.mounted) return;
                        Navigator.popUntil(
                          context,
                          ModalRoute.withName(AppRoutes.home),
                        );
                      },
              ),
            ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _scenarioLabel(DetectionScenario scenario) =>
      switch (scenario) {
        DetectionScenario.low => 'LOW',
        DetectionScenario.medium => 'MEDIUM',
        DetectionScenario.critical => 'CRITICAL',
      };
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.liveMode,
    required this.liveStarting,
    required this.onDemoSelected,
    required this.onLiveSelected,
  });

  final bool liveMode;
  final bool liveStarting;
  final VoidCallback? onDemoSelected;
  final VoidCallback? onLiveSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFEDEFF5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ToggleSegment(
            label: 'Demo Mode',
            selected: !liveMode,
            onTap: onDemoSelected,
          ),
        ),
        Expanded(
          child: _ToggleSegment(
            label: liveStarting ? 'Starting…' : 'Live Mode',
            selected: liveMode,
            onTap: onLiveSelected,
          ),
        ),
      ],
    ),
  );
}

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        boxShadow: selected
            ? const [BoxShadow(color: Colors.black12, blurRadius: 5)]
            : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? AppColors.text : AppColors.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _Waveform extends StatelessWidget {
  const _Waveform({this.levels});

  final List<double>? levels;

  @override
  Widget build(BuildContext context) {
    const barCount = 23;
    const demoHeights = [8.0, 14.0, 22.0, 32.0, 18.0, 12.0];
    final realLevels = levels;

    return SizedBox(
      height: 38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(barCount, (i) {
          double height;
          double alpha;
          if (realLevels != null && realLevels.isNotEmpty) {
            final offset = barCount - realLevels.length;
            if (i < offset) {
              height = 6;
              alpha = .25;
            } else {
              final amplitude = realLevels[i - offset];
              height = 6 + (amplitude * 32).clamp(0.0, 32.0).toDouble();
              alpha = .35 + (amplitude * .5).clamp(0.0, .5).toDouble();
            }
          } else {
            height = demoHeights[i % demoHeights.length];
            alpha = .35 + (i % 3) * .2;
          }
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              color: AppColors.safe.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}
