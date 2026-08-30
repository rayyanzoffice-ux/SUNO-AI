import 'dart:async';

import '../../models/detection_result.dart';
import '../audio/microphone_capture.dart';
import '../detection/suno_audio_classifier.dart';
import '../location/location_service.dart';
import '../ml/continuous_audio_detector.dart';
import '../ml/yamnet_stage.dart';
import '../motion/impact_stillness_detector.dart';
import '../risk/risk_engine.dart';
import 'detection_repository.dart';

/// Real on-device detection repository.
///
/// Pipeline: Microphone → AudioPreprocessor → YAMNet → SUNO Classifier →
///           ContinuousAudioDetector + ImpactStillnessDetector →
///           RiskEngine → DetectionResult.
///
/// Call [startMonitoring] to begin, [stopMonitoring] to release resources.
/// [onDetection] fires whenever a stable, non-zero-risk event is produced.
class LiveDetectionRepository implements DetectionRepository {
  LiveDetectionRepository({
    required this.yamnet,
    required this.classifier,
    required this.microphone,
    required this.locationService,
    RiskEngine? riskEngine,
    required void Function(DetectionResult) onDetection,
  }) : _riskEngine = riskEngine ?? const RiskEngine(),
       _onDetection = onDetection;

  final YamNetStage yamnet;
  final SunoAudioClassifier classifier;
  final MicrophoneCapture microphone;
  final LocationService locationService;
  final RiskEngine _riskEngine;
  final void Function(DetectionResult) _onDetection;

  ContinuousAudioDetector? _audioDetector;
  ImpactStillnessDetector? _motionDetector;
  StreamSubscription<dynamic>? _waveSub;
  Timer? _locationRefresh;

  bool _impactDetected = false;
  bool _stillnessDetected = false;
  LocationSnapshot? _lastLocation;

  Future<void> startMonitoring() async {
    // Refresh location every 30 seconds without blocking inference.
    _locationRefresh = Timer.periodic(const Duration(seconds: 30), (_) async {
      _lastLocation = await locationService.currentLocation();
    });
    // Initial location fetch (non-blocking).
    locationService.currentLocation().then((loc) => _lastLocation = loc);

    _motionDetector = ImpactStillnessDetector(
      onResult: (r) {
        _impactDetected = r.impactDetected;
        _stillnessDetected = r.stillnessDetected;
      },
    )..start();

    _audioDetector = ContinuousAudioDetector(
      yamnet: yamnet,
      classifier: classifier,
      onEvent: _onAudioEvent,
    );

    await microphone.start();
    _waveSub = microphone.waveforms.listen((frame) {
      _audioDetector?.process(frame);
    });
  }

  Future<void> stopMonitoring() async {
    _locationRefresh?.cancel();
    _locationRefresh = null;
    await _waveSub?.cancel();
    _waveSub = null;
    await microphone.stop();
    _motionDetector?.stop();
    _audioDetector?.reset();
    _impactDetected = false;
    _stillnessDetected = false;
  }

  void _onAudioEvent(AudioEvent event) {
    final impact = _impactDetected;
    final stillness = _stillnessDetected;
    // Reset motion flags after consuming them.
    _impactDetected = false;
    _stillnessDetected = false;

    final assessment = _riskEngine.evaluateDetection(
      detectedClass: event.label,
      confidence: event.confidence,
      impactDetected: impact,
      stillnessDetected: stillness,
    );

    if (assessment.riskScore == 0) return;

    final loc = _lastLocation;
    final result = DetectionResult(
      eventType: _eventTypeFor(event.label),
      confidence: event.confidence,
      impactDetected: impact,
      stillnessDetected: stillness,
      riskScore: assessment.riskScore,
      riskLevel: assessment.riskLevel,
      latitude: loc?.latitude,
      longitude: loc?.longitude,
      locationText: loc != null
          ? '${loc.latitude.toStringAsFixed(4)}, '
            '${loc.longitude.toStringAsFixed(4)}'
          : null,
      detectedAt: event.detectedAt,
    );

    _onDetection(result);
  }

  @override
  Future<DetectionResult> detect() {
    final completer = Completer<DetectionResult>();
    void handler(DetectionResult r) {
      if (!completer.isCompleted) completer.complete(r);
    }

    final detector = ContinuousAudioDetector(
      yamnet: yamnet,
      classifier: classifier,
      onEvent: (e) {
        final loc = _lastLocation;
        final a = _riskEngine.evaluateDetection(
          detectedClass: e.label,
          confidence: e.confidence,
          impactDetected: false,
          stillnessDetected: false,
        );
        if (a.riskScore > 0) {
          handler(DetectionResult(
            eventType: _eventTypeFor(e.label),
            confidence: e.confidence,
            impactDetected: false,
            stillnessDetected: false,
            riskScore: a.riskScore,
            riskLevel: a.riskLevel,
            latitude: loc?.latitude,
            longitude: loc?.longitude,
            locationText: loc != null
                ? '${loc.latitude.toStringAsFixed(4)}, '
                  '${loc.longitude.toStringAsFixed(4)}'
                : null,
            detectedAt: e.detectedAt,
          ));
        }
      },
    );

    StreamSubscription<dynamic>? sub;
    sub = microphone.waveforms.listen((frame) {
      detector.process(frame);
      if (completer.isCompleted) sub?.cancel();
    });

    return completer.future;
  }

  static String _eventTypeFor(String label) => switch (label) {
    'distress_voice' => 'Distress Sound',
    'alarm_siren' => 'Emergency Alarm',
    'breaking_crash' => 'Impact / Breaking Sound',
    _ => 'Ambient Sound',
  };
}
