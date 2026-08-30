import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/audio/microphone_capture.dart';
import '../../backend/detection/live_detection_repository.dart';
import '../../backend/detection/suno_audio_classifier.dart';
import '../../backend/location/location_service.dart';
import '../../backend/ml/yamnet_stage.dart';
import '../../backend/services/foreground_service_bridge.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
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
  bool detecting = false;
  late DetectionScenario selectedScenario;

  bool _liveMode = false;
  bool _liveStarting = false;
  bool _liveActive = false;
  String? _liveError;

  LiveDetectionRepository? _liveRepo;
  YamNetStage? _yamnet;
  MicrophoneCapture? _microphone;
  StreamSubscription<dynamic>? _levelSub;
  final List<double> _liveLevels = [];

  SunoRuntimeService get _runtime =>
      widget.runtime ?? SunoRuntimeService.instance;

  @override
  void initState() {
    super.initState();
    selectedScenario = widget.scenario;
  }

  Future<void> _simulate() async {
    setState(() => detecting = true);
    final result = await _runtime.runDetection(selectedScenario);
    if (!mounted) return;
    if (result.riskLevel == RiskLevel.low) {
      setState(() => detecting = false);
      return;
    }
    await _runtime.recordDetection(result);
    if (!mounted) return;
    final route = result.riskLevel == RiskLevel.medium
        ? AppRoutes.safetyCheck
        : AppRoutes.emergencyAlert;
    Navigator.pushReplacementNamed(context, route);
  }

  Future<void> _enableLiveMode() async {
    setState(() {
      _liveMode = true;
      _liveStarting = true;
      _liveError = null;
    });

    MicrophoneCapture? microphone;
    YamNetStage? yamnet;
    try {
      microphone = MicrophoneCapture();
      yamnet = await YamNetStage.load();
      final classifier = await SunoAudioClassifier.load();
      final repo = LiveDetectionRepository(
        yamnet: yamnet,
        classifier: classifier,
        microphone: microphone,
        locationService: LocationService(),
        onDetection: _onLiveDetection,
      );

      await repo.startMonitoring();
      await ForegroundServiceBridge.start();

      if (!mounted) {
        await repo.stopMonitoring();
        yamnet.close();
        await microphone.dispose();
        return;
      }

      // Separate subscription purely for the waveform visualization — the
      // ML pipeline consumes the same broadcast stream independently inside
      // LiveDetectionRepository, so this never interferes with detection.
      _levelSub = microphone.waveforms.listen((frame) {
        if (!mounted) return;
        setState(() {
          _liveLevels.add(frame.rmsAmplitude);
          if (_liveLevels.length > 23) _liveLevels.removeAt(0);
        });
      });

      setState(() {
        _yamnet = yamnet;
        _microphone = microphone;
        _liveRepo = repo;
        _liveStarting = false;
        _liveActive = true;
      });
    } on MicrophonePermissionException catch (e) {
      yamnet?.close();
      await microphone?.dispose();
      if (!mounted) return;
      setState(() {
        _liveStarting = false;
        _liveActive = false;
        _liveMode = false;
        _liveError = e.message;
      });
    } catch (e) {
      yamnet?.close();
      await microphone?.dispose();
      if (!mounted) return;
      setState(() {
        _liveStarting = false;
        _liveActive = false;
        _liveMode = false;
        _liveError = 'Live Mode failed to start: $e';
      });
    }
  }

  Future<void> _disableLiveMode() async {
    final repo = _liveRepo;
    final microphone = _microphone;
    final yamnet = _yamnet;
    _liveRepo = null;
    _microphone = null;
    _yamnet = null;

    await _levelSub?.cancel();
    _levelSub = null;
    await repo?.stopMonitoring();
    yamnet?.close();
    await microphone?.dispose();
    await ForegroundServiceBridge.stop();

    if (!mounted) return;
    setState(() {
      _liveActive = false;
      _liveMode = false;
      _liveLevels.clear();
    });
  }

  void _onLiveDetection(DetectionResult result) {
    if (!mounted) return;
    // Low risk stays silent — keep listening, no incident, no interruption.
    if (result.riskLevel == RiskLevel.low) return;

    _runtime.recordDetection(result).then((_) async {
      if (!mounted) return;
      final route = result.riskLevel == RiskLevel.medium
          ? AppRoutes.safetyCheck
          : AppRoutes.emergencyAlert;
      // Release the microphone before navigating away — Safety Check and
      // Emergency Alert don't need the live pipeline running behind them.
      await _disableLiveMode();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    });
  }

  @override
  void dispose() {
    if (_liveActive) {
      _levelSub?.cancel();
      _liveRepo?.stopMonitoring();
      _yamnet?.close();
      _microphone?.dispose();
      ForegroundServiceBridge.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                    liveMode: _liveMode,
                    liveStarting: _liveStarting,
                    onDemoSelected: _liveMode ? _disableLiveMode : null,
                    onLiveSelected: _liveMode ? null : _enableLiveMode,
                  ),
                  if (_liveError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.emergency.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _liveError!,
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
                      child: const Icon(
                        Icons.mic_rounded,
                        color: AppColors.safe,
                        size: 58,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _liveMode ? 'SUNO is Listening Live' : 'SUNO is Active',
                    style: const TextStyle(
                      color: AppColors.safe,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _liveMode
                        ? 'Real microphone, motion, and location — processed on this device'
                        : 'Listening privately on this device',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Long-press the mic for Silent SOS',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 18),
                  _Waveform(levels: _liveMode ? _liveLevels : null),
                  const SizedBox(height: 24),
                  if (!_liveMode) ...[
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: DetectionScenario.values.map((scenario) {
                        final selected = selectedScenario == scenario;
                        return ChoiceChip(
                          label: Text(_scenarioLabel(scenario)),
                          selected: selected,
                          onSelected: detecting
                              ? null
                              : (_) => setState(
                                  () => selectedScenario = scenario,
                                ),
                          selectedColor: AppColors.purple.withValues(
                            alpha: .14,
                          ),
                          checkmarkColor: AppColors.purple,
                          labelStyle: TextStyle(
                            color: selected
                                ? AppColors.purple
                                : AppColors.text,
                            fontWeight: FontWeight.w800,
                          ),
                          side: BorderSide(
                            color: selected
                                ? AppColors.purple
                                : AppColors.border,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: StatusChip(
                          label: 'Sound',
                          value: _liveMode
                              ? (_liveActive ? 'Listening' : 'Starting…')
                              : 'Normal',
                          color: AppColors.safe,
                          icon: Icons.graphic_eq_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatusChip(
                          label: 'Motion',
                          value: _liveMode ? 'Sensing' : 'Stable',
                          color: AppColors.safe,
                          icon: Icons.screen_rotation_alt_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatusChip(
                          label: 'Location',
                          value: _liveMode ? 'GPS' : 'Demo',
                          color: AppColors.safe,
                          icon: Icons.wifi_rounded,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (detecting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Analyzing ${_scenarioLabel(selectedScenario).toLowerCase()} risk…',
                        style: const TextStyle(
                          color: AppColors.emergency,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (!_liveMode)
                    OutlinedButton.icon(
                      onPressed: detecting ? null : _simulate,
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: Text(
                        detecting ? 'Analyzing…' : 'Demo: Simulate Distress',
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
                  const SizedBox(height: 5),
                  PrimaryActionButton(
                    label: 'STOP MONITORING',
                    outlined: true,
                    color: AppColors.emergency,
                    icon: Icons.stop_circle_outlined,
                    onPressed: detecting
                        ? null
                        : () async {
                            if (_liveMode) await _disableLiveMode();
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

  /// Real microphone amplitude levels (0..1) when in Live Mode, most recent
  /// last. Null falls back to the static Demo Mode animation.
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
            // Right-align real samples so the most recent value is the
            // rightmost bar, matching a left-to-right time axis.
            final offset = barCount - realLevels.length;
            if (i < offset) {
              height = 6.0;
              alpha = .25;
            } else {
              final amplitude = realLevels[i - offset];
              height = 6.0 + (amplitude * 32.0).clamp(0.0, 32.0);
              alpha = .35 + (amplitude * .5).clamp(0.0, .5);
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

