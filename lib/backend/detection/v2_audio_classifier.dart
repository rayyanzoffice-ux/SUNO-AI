import 'package:tflite_flutter/tflite_flutter.dart';

import 'classifier_labels.dart';
import 'suno_audio_classifier.dart';

/// Runtime adapter for the 23-class classifier trained by the v2 notebook.
///
/// Unlike [SunoAudioClassifier], the output width is taken from `labels_v2.json`
/// and checked against the TFLite output tensor at load time. A mismatch is
/// fatal because probabilities mapped to the wrong class names would mislabel
/// every detection without ever crashing.
class V2AudioClassifier implements SunoAudioClassifier {
  V2AudioClassifier._({
    required Interpreter interpreter,
    required this.labelSet,
  }) : _interpreter = interpreter;

  static const modelAsset = 'assets/ml/suno_audio_classifier_v2.tflite';
  static const labelsAsset = 'assets/ml/labels_v2.json';

  final Interpreter _interpreter;
  final ClassifierLabels labelSet;

  bool _closed = false;

  @override
  List<String> get labels => labelSet.classes;

  /// The detector's debounce gate. Per-class thresholds are applied later by
  /// [alertWeightFor]; this only keeps clearly uncertain frames out.
  @override
  double get confidenceThreshold => labelSet.minimumAlertThreshold;

  static Future<V2AudioClassifier> load() async {
    final labelSet = await ClassifierLabels.loadFromAsset(labelsAsset);
    final interpreter = await Interpreter.fromAsset(modelAsset);
    var success = false;

    try {
      interpreter.allocateTensors();

      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);
      final inputShape = inputTensor.shape;
      final outputShape = outputTensor.shape;

      if (inputShape.length != 2 ||
          inputShape[0] != 1 ||
          inputShape[1] != ClassifierLabels.expectedEmbeddingSize) {
        throw FormatException(
          'Unexpected v2 classifier input shape: $inputShape; '
          'expected [1, ${ClassifierLabels.expectedEmbeddingSize}].',
        );
      }

      if (outputShape.length != 2 ||
          outputShape[0] != 1 ||
          outputShape[1] != labelSet.classes.length) {
        throw FormatException(
          'v2 classifier output shape $outputShape does not match '
          'labels_v2.json (${labelSet.classes.length} classes). '
          'Refusing to map probabilities onto the wrong labels.',
        );
      }

      if (inputTensor.type != TensorType.float32 ||
          outputTensor.type != TensorType.float32) {
        throw const FormatException(
          'v2 classifier tensors must both be float32.',
        );
      }

      success = true;
      return V2AudioClassifier._(
        interpreter: interpreter,
        labelSet: labelSet,
      );
    } finally {
      if (!success) {
        interpreter.close();
      }
    }
  }

  @override
  SunoClassification classifyEmbedding(List<double> embedding) {
    if (_closed) {
      throw StateError('V2AudioClassifier has already been closed.');
    }
    if (embedding.length != ClassifierLabels.expectedEmbeddingSize) {
      throw ArgumentError.value(
        embedding.length,
        'embedding.length',
        'Expected exactly ${ClassifierLabels.expectedEmbeddingSize} values.',
      );
    }
    for (final value in embedding) {
      if (!value.isFinite) {
        throw ArgumentError('Embedding contains a non-finite value: $value.');
      }
    }

    final input = <List<double>>[List<double>.from(embedding)];
    final output = <List<double>>[
      List<double>.filled(labels.length, 0.0),
    ];

    _interpreter.run(input, output);

    final scores = output[0];
    for (final score in scores) {
      if (!score.isFinite || score < 0 || score > 1) {
        throw StateError('Classifier returned an invalid probability: $score');
      }
    }

    var best = 0;
    var second = -1;
    for (var index = 1; index < scores.length; index++) {
      if (scores[index] > scores[best]) {
        second = best;
        best = index;
      } else if (second < 0 || scores[index] > scores[second]) {
        second = index;
      }
    }

    return SunoClassification(
      label: labels[best],
      confidence: scores[best],
      index: best,
      secondConfidence: second < 0 ? 0.0 : scores[second],
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _interpreter.close();
  }
}

/// Human-readable event type stored in Hive and sent to contacts.
///
/// These English strings are a persisted contract; [localizedEventType]
/// translates them at render time.
String eventTypeForV2(String label) => switch (label) {
  'a01_scream_loud' => 'Distress Sound',
  'a02_gun_shots' => 'Gunshot Sound',
  'a03_glass_break' || 'a04_crash_heavy' => 'Impact / Breaking Sound',
  'a05_alarm_home' => 'Emergency Alarm',
  _ => 'Ambient Sound',
};
