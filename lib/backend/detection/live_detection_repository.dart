import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../../models/detection_result.dart';
import '../audio/microphone_capture.dart';
import '../location/location_service.dart';
import '../ml/continuous_audio_detector.dart';
import '../ml/yamnet_stage.dart';
import '../motion/impact_stillness_detector.dart';
import '../risk/risk_engine.dart';
import 'alert_pattern_tracker.dart';
import 'classifier_labels.dart';
import 'detection_repository.dart';
import 'loudness_gate.dart';
import 'suno_audio_classifier.dart';
import 'v2_audio_classifier.dart';

/// v1 voice and alarm classes need a second detection inside the pattern
/// window before they open the safety check. One ~2 s loud sound (a shout, a
/// laugh, a TV line) is too ambiguous to act on alone. A real impact is
/// meaningful on one hit, so `breaking_crash` stays exempt.
const _v1RepeatRequiredClasses = <String>{'distress_voice', 'alarm_siren'};

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
    bool modelV2 = false,
    ClassifierLabels? labelSet,
    LoudnessGate loudnessGate = const LoudnessGate(),
    AlertPatternTracker? patternTracker,
  }) : _riskEngine = riskEngine ?? const RiskEngine(),
       _modelV2 = modelV2,
       _labelSet = labelSet,
       _loudnessGate = loudnessGate,
       _patternTracker = patternTracker ?? AlertPatternTracker(),
       _lastLocation = initialLocation {
    if (modelV2 && labelSet == null) {
      throw ArgumentError('labelSet is required when modelV2 is enabled.');
    }
  }

  final YamNetStage yamnet;
  final SunoAudioClassifier classifier;
  final MicrophoneCapture microphone;
  final LocationService locationService;
  final void Function(Object) onError;
  final void Function(Object)? onMotionError;
  final RiskEngine _riskEngine;
  final Stream<UserAccelerometerEvent>? _motionEvents;
  final void Function(DetectionResult) _onDetection;
  final bool _modelV2;
  final ClassifierLabels? _labelSet;
  final LoudnessGate _loudnessGate;
  final AlertPatternTracker _patternTracker;
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
        averageEmbeddings: _modelV2,
        isAlertLabel: _modelV2
            ? (label) => _labelSet!.isAlert(label)
            : null,
        onEvent: _onAudioEvent,
      );
      _waveSub = microphone.waveforms.listen((frame) {
        if (!_monitoring) return;
        try {
          _audioDetector?.process(frame);
        } catch (error) {
          onError(error);
        }
      }, onError: onError);
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
    _patternTracker.reset();
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
    if (_modelV2) {
      _onAudioEventV2(event);
      return;
    }
    if (_v1RepeatRequiredClasses.contains(event.label)) {
      _patternTracker.record(event);
      if (!_patternTracker.hasRepeated(event.label, minRepeats: 2)) {
        return; // first hit noted; wait for a second inside the window
      }
    }
    final motion = _motion;
    final age = motion == null
        ? null
        : event.detectedAt.difference(motion.capturedAt);
    final fresh =
        age != null && !age.isNegative && age <= const Duration(seconds: 5);
    // Motion only ever contributes alongside a validated danger-class sound.
    // ambient_safe (or any future non-distress label) must never open the
    // safety-check pathway on motion evidence alone, and must not consume
    // motion that a real distress sound arriving moments later still needs.
    final consumesMotion =
        fresh && distressAudioClasses.contains(event.label);
    final impact = consumesMotion && motion!.impactDetected;
    final stillness = consumesMotion && motion!.stillnessDetected;
    if (consumesMotion) _motion = null;
    final assessment = _riskEngine.evaluateDetection(
      detectedClass: event.label,
      confidence: event.confidence,
      impactDetected: impact,
      stillnessDetected: stillness,
    );
    _completeDetection(
      event: event,
      eventType: switch (event.label) {
        'distress_voice' => 'Distress Sound',
        'alarm_siren' => 'Emergency Alarm',
        'breaking_crash' => 'Impact / Breaking Sound',
        _ => 'Ambient Sound',
      },
      impact: impact,
      stillness: stillness,
      assessment: assessment,
    );
  }

  /// v2 path: per-class confidence, margin, loudness, and pattern evidence.
  ///
  /// A single confirmed alert class still goes through the safety-check
  /// countdown. Only repeated or compound evidence is forced to critical.
  void _onAudioEventV2(AudioEvent event) {
    final labels = _labelSet!;
    if (event.confidence - event.secondConfidence < labels.margin) return;
    if (alertWeightFor(event.label, event.confidence, labels) == 0) return;
    if (!_loudnessGate.allows(event)) return;

    final motion = _motion;
    final age = motion == null
        ? null
        : event.detectedAt.difference(motion.capturedAt);
    final fresh =
        age != null && !age.isNegative && age <= const Duration(seconds: 5);
    final impact = fresh && motion!.impactDetected;
    final stillness = fresh && motion!.stillnessDetected;
    _motion = null;

    _patternTracker.record(event);
    final forceCritical = shouldEscalateImmediately(
      _patternTracker,
      labels,
      event,
    );
    final assessment = _riskEngine.evaluateV2Detection(
      detectedClass: event.label,
      confidence: event.confidence,
      impactDetected: impact,
      stillnessDetected: stillness,
      labels: labels,
      forceCritical: forceCritical,
    );
    _completeDetection(
      event: event,
      eventType: eventTypeForV2(event.label),
      impact: impact,
      stillness: stillness,
      assessment: assessment,
    );
  }

  void _completeDetection({
    required AudioEvent event,
    required String eventType,
    required bool impact,
    required bool stillness,
    required RiskAssessment assessment,
  }) {
    if (assessment.riskScore == 0) return;
    final location = _lastLocation;
    final recentLocation =
        location != null &&
        event.detectedAt.difference(location.capturedAt).abs() <=
            const Duration(minutes: 1);
    final result = DetectionResult(
      eventType: eventType,
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
