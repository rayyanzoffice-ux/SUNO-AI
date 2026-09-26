import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/detection_result.dart';
import '../audio/microphone_capture.dart';
import '../location/location_service.dart';
import '../ml/continuous_audio_detector.dart';
import '../ml/yamnet_stage.dart';
import '../motion/impact_stillness_detector.dart';
import '../risk/risk_engine.dart';
import 'detection_repository.dart';
import 'suno_audio_classifier.dart';

class LiveDetectionRepository implements DetectionRepository {
  LiveDetectionRepository({
    required this.yamnet,
    required this.classifier,
    required this.microphone,
    required this.locationService,
    required this.onError,
    required this._onDetection,
    this.onMotionError,
    LocationSnapshot? initialLocation,
    this._motionEvents,
    RiskEngine? riskEngine,
  }) : _riskEngine = riskEngine ?? const RiskEngine(),
       _lastLocation = initialLocation;

  final YamNetStage yamnet;
  final SunoAudioClassifier classifier;
  final MicrophoneCapture microphone;
  final LocationService locationService;
  final void Function(Object) onError;
  final void Function(Object)? onMotionError;
  final RiskEngine _riskEngine;
  final Stream<UserAccelerometerEvent>? _motionEvents;
  final void Function(DetectionResult) _onDetection;
  ContinuousAudioDetector? _audioDetector;
  ImpactStillnessDetector? _motionDetector;
  StreamSubscription<dynamic>? _waveSub;
  Timer? _locationRefresh;
  MotionResult? _motion;
  LocationSnapshot? _lastLocation;
  Completer<DetectionResult>? _nextDetection;
  bool _monitoring = false;

  Future<void> startMonitoring() async {
    if (_monitoring) return;
    _monitoring = true;
    try {
      _locationRefresh = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshLocation(),
      );
      try {
        _motionDetector = ImpactStillnessDetector(
          events: _motionEvents,
          onResult: (result) => _motion = result,
          onError: _onMotionSensorError,
        )..start();
      } catch (error) {
        // Sensor stream setup can fail synchronously on devices without a
        // usable motion sensor. Keep the audio path available in that case.
        _motionDetector = null;
        onMotionError?.call(error);
      }
      _audioDetector = ContinuousAudioDetector(
        yamnet: yamnet,
        classifier: classifier,
        onEvent: _onAudioEvent,
      );
      _waveSub = microphone.waveforms.listen((frame) {
        if (!_monitoring) return;
        try {
          _audioDetector?.process(frame);
        } catch (error, stack) {
          // TEMP DEBUG (Problem 1) — remove before shipping.
          debugPrint('SUNO_DEBUG inference threw: $error\n$stack');
          onError(error);
        }
      }, onError: (Object error, StackTrace stack) {
        // TEMP DEBUG (Problem 1) — remove before shipping.
        debugPrint('SUNO_DEBUG microphone stream error: $error\n$stack');
        onError(error);
      });
      await microphone.start();
    } catch (_) {
      await stopMonitoring();
      rethrow;
    }
  }

  void _onMotionSensorError(Object error) {
    // Motion is an optional signal. Disable it after a sensor failure while
    // leaving the audio pipeline running.
    final detector = _motionDetector;
    _motionDetector = null;
    _motion = null;
    unawaited(detector?.stop());
    onMotionError?.call(error);
  }

  Future<void> _refreshLocation() async {
    final position = await locationService.currentLocation(
      requestPermission: false,
    );
    if (_monitoring) _lastLocation = position;
  }

  Future<void> stopMonitoring() async {
    _monitoring = false;
    _locationRefresh?.cancel();
    _locationRefresh = null;
    final waveSub = _waveSub;
    final motionDetector = _motionDetector;
    final next = _nextDetection;
    _waveSub = null;
    _motionDetector = null;
    _nextDetection = null;
    _audioDetector?.reset();
    _audioDetector = null;
    _motion = null;
    if (next != null && !next.isCompleted) {
      next.completeError(StateError('Monitoring stopped before detection.'));
    }
    try {
      await waveSub?.cancel();
    } finally {
      try {
        await motionDetector?.stop();
      } finally {
        await microphone.stop();
      }
    }
  }

  void _onAudioEvent(AudioEvent event) {
    final motion = _motion;
    final age = motion == null
        ? null
        : event.detectedAt.difference(motion.capturedAt);
    final fresh =
        age != null && !age.isNegative && age <= const Duration(seconds: 5);
    final impact = fresh && motion!.impactDetected;
    final stillness = fresh && motion!.stillnessDetected;
    _motion = null;
    final assessment = _riskEngine.evaluateDetection(
      detectedClass: event.label,
      confidence: event.confidence,
      impactDetected: impact,
      stillnessDetected: stillness,
    );
    if (assessment.riskScore == 0) return;
    final location = _lastLocation;
    final recentLocation =
        location != null &&
        event.detectedAt.difference(location.capturedAt).abs() <=
            const Duration(minutes: 1);
    final result = DetectionResult(
      eventType: switch (event.label) {
        'distress_voice' => 'Distress Sound',
        'alarm_siren' => 'Emergency Alarm',
        'breaking_crash' => 'Impact / Breaking Sound',
        _ => 'Ambient Sound',
      },
      confidence: event.confidence,
      impactDetected: impact,
      stillnessDetected: stillness,
      riskScore: assessment.riskScore,
      riskLevel: assessment.riskLevel,
      latitude: recentLocation ? location.latitude : null,
      longitude: recentLocation ? location.longitude : null,
      locationText: recentLocation ? location.description : null,
      detectedAt: event.detectedAt,
    );
    final next = _nextDetection;
    if (next != null && !next.isCompleted) next.complete(result);
    _nextDetection = null;
    _onDetection(result);
  }

  @override
  Future<DetectionResult> detect() {
    if (!_monitoring) {
      throw StateError('Start monitoring before requesting a detection.');
    }
    final next = _nextDetection ??= Completer<DetectionResult>();
    return next.future.timeout(const Duration(seconds: 30)).whenComplete(() {
      if (identical(_nextDetection, next)) _nextDetection = null;
    });
  }
}
