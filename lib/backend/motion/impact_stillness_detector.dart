import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// Output of the motion analysis after a candidate impact event.
class MotionResult {
  const MotionResult({
    required this.impactDetected,
    required this.stillnessDetected,
    required this.peakMagnitude,
    required this.capturedAt,
  });

  final bool impactDetected;
  final bool stillnessDetected;
  final double peakMagnitude;
  final DateTime capturedAt;
}

/// Monitors the accelerometer for sudden impacts and post-impact stillness.
///
/// An impact candidate is detected when acceleration magnitude exceeds
/// [impactThreshold]. After a candidate, a [postImpactWindowMs]-ms
/// observation window begins; if average magnitude drops below
/// [stillnessThreshold], stillness is confirmed.
class ImpactStillnessDetector {
  ImpactStillnessDetector({
    this.impactThreshold = 25.0,
    this.stillnessThreshold = 3.0,
    this.postImpactWindowMs = 2000,
    void Function(MotionResult)? onResult,
  }) : _onResult = onResult;

  final double impactThreshold;
  final double stillnessThreshold;
  final int postImpactWindowMs;
  final void Function(MotionResult)? _onResult;

  StreamSubscription<AccelerometerEvent>? _sub;
  bool _observingPostImpact = false;
  Timer? _postImpactTimer;
  double _peakMagnitude = 0;
  final List<double> _postImpactSamples = [];

  bool get isListening => _sub != null;

  void start() {
    _sub ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccelerometer);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _postImpactTimer?.cancel();
    _observingPostImpact = false;
    _postImpactSamples.clear();
    _peakMagnitude = 0;
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final mag =
        sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

    if (!_observingPostImpact && mag >= impactThreshold) {
      _observingPostImpact = true;
      _peakMagnitude = mag;
      _postImpactSamples.clear();
      _postImpactTimer?.cancel();
      _postImpactTimer = Timer(
        Duration(milliseconds: postImpactWindowMs),
        _evaluatePostImpact,
      );
    } else if (_observingPostImpact) {
      if (mag > _peakMagnitude) _peakMagnitude = mag;
      _postImpactSamples.add(mag);
    }
  }

  void _evaluatePostImpact() {
    final avg = _postImpactSamples.isEmpty
        ? 0.0
        : _postImpactSamples.reduce((a, b) => a + b) /
              _postImpactSamples.length;

    _onResult?.call(MotionResult(
      impactDetected: true,
      stillnessDetected: avg <= stillnessThreshold,
      peakMagnitude: _peakMagnitude,
      capturedAt: DateTime.now(),
    ));

    _observingPostImpact = false;
    _postImpactSamples.clear();
    _peakMagnitude = 0;
  }

  void dispose() => stop();
}
