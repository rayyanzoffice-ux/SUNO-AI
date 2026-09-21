import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:suno_ai/backend/audio/audio_preprocessor.dart';
import 'package:suno_ai/backend/audio/audio_waveform.dart';
import 'package:suno_ai/backend/audio/microphone_capture.dart';
import 'package:suno_ai/backend/detection/live_detection_repository.dart';
import 'package:suno_ai/backend/location/location_service.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/backend/detection/suno_audio_classifier.dart';
import 'package:suno_ai/backend/ml/continuous_audio_detector.dart';
import 'package:suno_ai/backend/ml/yamnet_stage.dart';
import 'package:suno_ai/backend/motion/impact_stillness_detector.dart';

void main() {
  test('resampling is independent of odd and uneven PCM chunks', () {
    final bytes = Uint8List(44100 * 4);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length ~/ 2; i++) {
      data.setInt16(i * 2, (sin(i * .071) * 30000).round(), Endian.little);
    }
    final whole = AudioPreprocessor().feed(bytes);
    final chunked = AudioPreprocessor();
    final frames = <AudioWaveform>[];
    final random = Random(42);
    for (var offset = 0; offset < bytes.length;) {
      final end = min(bytes.length, offset + 1 + random.nextInt(4096));
      frames.addAll(chunked.feed(Uint8List.sublistView(bytes, offset, end)));
      offset = end;
    }
    expect(whole.length, 3);
    expect(frames.length, whole.length);
    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].samples, orderedEquals(whole[i].samples));
      expect(frames[i].sampleRate, 16000);
      expect(frames[i].samples.length, 15360);
    }
  });

  test('reset discards carried byte, previous samples and phase', () {
    final processor = AudioPreprocessor(frameLength: 4, frameHop: 2);
    processor.feed(Uint8List.fromList([255, 127, 255]));
    processor.reset();
    final silence = Uint8List(40);
    expect(
      processor.feed(silence).map((f) => f.samples),
      AudioPreprocessor(
        frameLength: 4,
        frameHop: 2,
      ).feed(silence).map((f) => f.samples),
    );
  });

  test('ambient detection does not suppress following sustained distress', () {
    final classifier = _Classifier();
    final events = <AudioEvent>[];
    final detector = ContinuousAudioDetector(
      yamnet: _Yamnet(),
      classifier: classifier,
      onEvent: events.add,
    );
    final waveform = AudioWaveform(
      samples: const [],
      sampleRate: 16000,
      capturedAt: DateTime(2026),
    );
    for (var i = 0; i < 3; i++) {
      detector.process(waveform);
    }
    classifier.label = 'distress_voice';
    for (var i = 0; i < 3; i++) {
      detector.process(waveform);
    }
    expect(events.map((e) => e.label), ['ambient_safe', 'distress_voice']);
    for (var i = 0; i < 6; i++) {
      detector.process(waveform);
    }
    expect(events.length, 2);
    detector.process(waveform);
    expect(events.length, 3);
    detector.reset();
    detector.process(waveform);
    expect(events.length, 3);
  });

  testWidgets('impact without subsequent sensor samples is not stillness', (
    tester,
  ) async {
    final events = StreamController<UserAccelerometerEvent>();
    final results = <MotionResult>[];
    final detector = ImpactStillnessDetector(
      events: events.stream,
      onResult: results.add,
    )..start();
    events.add(UserAccelerometerEvent(20, 0, 0, DateTime.now()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(results.single.impactDetected, isTrue);
    expect(results.single.stillnessDetected, isFalse);
    await tester.runAsync(() async {
      await detector.dispose();
      await events.close();
    });
  });

  testWidgets(
    'motion stillness requires samples and stop cancels pending result',
    (tester) async {
      final events = StreamController<UserAccelerometerEvent>();
      final results = <MotionResult>[];
      final errors = <Object>[];
      final detector = ImpactStillnessDetector(
        events: events.stream,
        onResult: results.add,
        onError: errors.add,
      )..start();
      events.add(UserAccelerometerEvent(20, 0, 0, DateTime.now()));
      events.add(UserAccelerometerEvent(.1, .1, .1, DateTime.now()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(results.single.stillnessDetected, isTrue);
      events.addError(StateError('sensor unavailable'));
      events.add(UserAccelerometerEvent(30, 0, 0, DateTime.now()));
      await tester.pump();
      expect(errors, hasLength(1));
      await tester.runAsync(detector.stop);
      await tester.pump(const Duration(seconds: 3));
      expect(results, hasLength(1));
      expect(detector.isListening, isFalse);
      await tester.runAsync(events.close);
    },
  );
  for (final age in [
    const Duration(seconds: -10),
    Duration.zero,
    const Duration(seconds: 10),
  ]) {
    testWidgets('Live consumes motion once and ignores invalid age $age', (
      tester,
    ) async {
      final motion = StreamController<UserAccelerometerEvent>();
      final microphone = _Microphone();
      final results = <DetectionResult>[];
      final repository = LiveDetectionRepository(
        yamnet: _Yamnet(),
        classifier: _Classifier()..label = 'distress_voice',
        microphone: microphone,
        locationService: LocationService(),
        motionEvents: motion.stream,
        initialLocation: LocationSnapshot(
          latitude: 33,
          longitude: 73,
          capturedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
        onError: (error) => fail('$error'),
        onDetection: results.add,
      );
      await repository.startMonitoring();
      motion.add(UserAccelerometerEvent(20, 0, 0, DateTime.now()));
      motion.add(UserAccelerometerEvent(0, 0, 0, DateTime.now()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      final frame = AudioWaveform(
        samples: const [],
        sampleRate: 16000,
        capturedAt: DateTime.now().add(
          age == Duration.zero ? const Duration(milliseconds: 1) : age,
        ),
      );
      for (var i = 0; i < 3; i++) {
        microphone.controller.add(frame);
      }
      await tester.pump();
      expect(results.single.impactDetected, age == Duration.zero);
      expect(results.single.stillnessDetected, age == Duration.zero);
      expect(results.single.riskScore, age == Duration.zero ? 95 : 50);
      expect(results.single.latitude, isNull);
      for (var i = 0; i < 7; i++) {
        microphone.controller.add(frame);
      }
      await tester.pump();
      expect(results.last.impactDetected, isFalse);
      expect(results.last.riskScore, 50);
      final waiting = repository.detect();
      final stopped = expectLater(waiting, throwsStateError);
      await tester.runAsync(repository.stopMonitoring);
      await tester.pump();
      await stopped;
      expect(microphone.stops, 1);
      expect(motion.hasListener, isFalse);
      await tester.runAsync(() async {
        await microphone.controller.close();
        await motion.close();
      });
    });
  }
}

class _Microphone extends Fake implements MicrophoneCapture {
  final controller = StreamController<AudioWaveform>.broadcast();
  int stops = 0;
  @override
  Stream<AudioWaveform> get waveforms => controller.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    stops++;
  }
}

class _Yamnet implements YamNetStage {
  @override
  List<YamNetEmbedding> embed(AudioWaveform waveform) => [
    YamNetEmbedding(embedding: List.filled(1024, 0), frameIndex: 0),
  ];
  @override
  void close() {}
}

class _Classifier implements SunoAudioClassifier {
  String label = 'ambient_safe';
  @override
  double get confidenceThreshold => .3;
  @override
  List<String> get labels => SunoAudioClassifier.expectedLabels;
  @override
  SunoClassification classifyEmbedding(List<double> embedding) =>
      SunoClassification(
        label: label,
        confidence: .9,
        index: labels.indexOf(label),
      );
  @override
  void close() {}
}
