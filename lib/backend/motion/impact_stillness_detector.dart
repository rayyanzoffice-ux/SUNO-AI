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

/// Monitors linear (gravity-compensated) acceleration for sudden impacts
/// and post-impact stillness.
///
/// Uses [userAccelerometerEventStream] rather than the raw accelerometer.
/// The raw sensor always reports ~9.8 m/s² of Earth's gravity baked into
/// every reading even when the phone is perfectly still, so thresholds
/// tuned against it would need an orientation-dependent gravity offset
/// subtracted first. [userAccelerometerEventStream] already removes that
/// component, so a resting phone reads close to 0 m/s² on all three axes
/// and [impactThreshold] / [stillnessThreshold] can be compared directly
/// against magnitude with no gravity bias.
class ImpactStillnessDetector {
  ImpactStillnessDetector({
    this.impactThreshold = 15.0,
    this.stillnessThreshold = 1.5,
    this.postImpactWindowMs = 2000,
    this._onResult,
    this._onError,
    this._events,
  });

  final void Function(Object)? _onError;
  final Stream<UserAccelerometerEvent>? _events;
  final double impactThreshold;
  final double stillnessThreshold;
  final int postImpactWindowMs;
  final void Function(MotionResult)? _onResult;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  bool _observingPostImpact = false;
  Timer? _postImpactTimer;
  double _peakMagnitude = 0;
  final List<double> _postImpactSamples = [];

  bool get isListening => _sub != null;

  void start() {
    _sub ??=
        (_events ??
                userAccelerometerEventStream(
                  samplingPeriod: SensorInterval.normalInterval,
                ))
            .listen(
              _onAccelerometer,
              onError: (Object error) => _onError?.call(error),
            );
  }

  Future<void> stop() async {
    final subscription = _sub;
    _sub = null;
    _postImpactTimer?.cancel();
    _observingPostImpact = false;
    _postImpactSamples.clear();
    _peakMagnitude = 0;
    await subscription?.cancel();
  }

  void _onAccelerometer(UserAccelerometerEvent event) {
    final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

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

    _onResult?.call(
      MotionResult(
        impactDetected: true,
        stillnessDetected:
            _postImpactSamples.isNotEmpty && avg <= stillnessThreshold,
        peakMagnitude: _peakMagnitude,
        capturedAt: DateTime.now(),
      ),
    );

    _observingPostImpact = false;
    _postImpactSamples.clear();
    _peakMagnitude = 0;
  }

  Future<void> dispose() => stop();
}
