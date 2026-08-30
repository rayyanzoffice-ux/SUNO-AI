import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/detection_result.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/primary_action_button.dart';
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

  @override
  void initState() {
    super.initState();
    selectedScenario = widget.scenario;
  }

  Future<void> _simulate() async {
    setState(() => detecting = true);
    final runtime = widget.runtime ?? SunoRuntimeService.instance;
    final result = await runtime.runDetection(selectedScenario);
    if (!mounted) return;
    if (result.riskLevel == RiskLevel.low) {
      setState(() => detecting = false);
      return;
    }
    await runtime.recordDetection(result);
    if (!mounted) return;
    final route = result.riskLevel == RiskLevel.medium
        ? AppRoutes.safetyCheck
        : AppRoutes.emergencyAlert;
    Navigator.pushReplacementNamed(context, route);
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
                  const SizedBox(height: 12),
                  Container(
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
                  const SizedBox(height: 22),
                  const Text(
                    'SUNO is Active',
                    style: TextStyle(
                      color: AppColors.safe,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Listening privately on this device',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 22),
                  const _Waveform(),
                  const SizedBox(height: 24),
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
                            : (_) =>
                                  setState(() => selectedScenario = scenario),
                        selectedColor: AppColors.purple.withValues(alpha: .14),
                        checkmarkColor: AppColors.purple,
                        labelStyle: TextStyle(
                          color: selected ? AppColors.purple : AppColors.text,
                          fontWeight: FontWeight.w800,
                        ),
                        side: BorderSide(
                          color: selected ? AppColors.purple : AppColors.border,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Expanded(
                        child: StatusChip(
                          label: 'Sound',
                          value: 'Normal',
                          color: AppColors.safe,
                          icon: Icons.graphic_eq_rounded,
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: StatusChip(
                          label: 'Motion',
                          value: 'Stable',
                          color: AppColors.safe,
                          icon: Icons.screen_rotation_alt_rounded,
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: StatusChip(
                          label: 'Connection',
                          value: 'Active',
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
                        style: TextStyle(
                          color: AppColors.emergency,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
                        : () => Navigator.popUntil(
                            context,
                            ModalRoute.withName(AppRoutes.home),
                          ),
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

class _Waveform extends StatelessWidget {
  const _Waveform();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(23, (i) {
        final heights = [8.0, 14.0, 22.0, 32.0, 18.0, 12.0];
        return Container(
          width: 3,
          height: heights[i % heights.length],
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          decoration: BoxDecoration(
            color: AppColors.safe.withValues(alpha: .35 + (i % 3) * .2),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    ),
  );
}
