import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// The probability output produced by the SUNO classifier head.
class SunoClassification {
  const SunoClassification({
    required this.label,
    required this.confidence,
    required this.index,
  });

  final String label;
  final double confidence;
  final int index;
}

/// Runtime adapter for the exported SUNO classifier head.
///
/// This model consumes one 1,024-value YAMNet embedding. It does not consume
/// raw microphone PCM. A deployable YAMNet embedding stage must be supplied
/// before this adapter becomes the live audio detector.
class SunoAudioClassifier {
  static const modelAsset = 'assets/ml/suno_audio_classifier.tflite';
  static const labelsAsset = 'assets/ml/labels.json';

  static const expectedEmbeddingSize = 1024;
  static const expectedClassCount = 4;

  static const expectedLabels = <String>[
    'ambient_safe',
    'distress_voice',
    'alarm_siren',
    'breaking_crash',
  ];

  SunoAudioClassifier._({
    required Interpreter interpreter,
    required List<String> labels,
    required this.confidenceThreshold,
  }) : _interpreter = interpreter,
       _labels = List.unmodifiable(labels);

  final Interpreter _interpreter;
  final List<String> _labels;
  final double confidenceThreshold;

  bool _closed = false;

  List<String> get labels => _labels;

  static Future<SunoAudioClassifier> load() async {
    final configText = await rootBundle.loadString(labelsAsset);
    final decoded = jsonDecode(configText);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'SUNO labels.json must contain an object.',
      );
    }

    final classes = decoded['classes'];
    final embeddingSize = decoded['embedding_size'];
    final sampleRate = decoded['sample_rate_hz'];
    final frameLength = decoded['frame_length_sec'];
    final frameHop = decoded['frame_hop_sec'];
    final threshold = decoded['confidence_threshold'];

    if (classes is! List || classes.length != expectedClassCount) {
      throw const FormatException(
        'SUNO classifier must define exactly four classes.',
      );
    }

    final labels = classes.map((value) {
      if (value is! String || value.isEmpty) {
        throw const FormatException(
          'SUNO class labels must be non-empty strings.',
        );
      }
      return value;
    }).toList(growable: false);

    if (!_sameLabels(labels, expectedLabels)) {
      throw FormatException(
        'SUNO class ordering does not match the model contract: $labels',
      );
    }

    if (embeddingSize != expectedEmbeddingSize) {
      throw const FormatException(
        'SUNO classifier requires 1024-dimensional YAMNet embeddings.',
      );
    }

    if (sampleRate != 16000) {
      throw const FormatException(
        'SUNO YAMNet input sample rate must be 16000 Hz.',
      );
    }

    if (frameLength != 0.96) {
      throw const FormatException(
        'SUNO YAMNet frame length must be 0.96 seconds.',
      );
    }

    if (frameHop != 0.48) {
      throw const FormatException(
        'SUNO YAMNet frame hop must be 0.48 seconds.',
      );
    }

    if (threshold is! num || threshold < 0 || threshold > 1) {
      throw const FormatException(
        'SUNO confidence_threshold must be between 0 and 1.',
      );
    }

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
          inputShape[1] != expectedEmbeddingSize) {
        throw FormatException(
          'Unexpected classifier input shape: $inputShape; '
          'expected [1, $expectedEmbeddingSize].',
        );
      }

      if (outputShape.length != 2 ||
          outputShape[0] != 1 ||
          outputShape[1] != expectedClassCount) {
        throw FormatException(
          'Unexpected classifier output shape: $outputShape; '
          'expected [1, $expectedClassCount].',
        );
      }

      if (inputTensor.type != TensorType.float32) {
        throw FormatException(
          'Unexpected classifier input type: ${inputTensor.type}; '
          'expected float32.',
        );
      }

      if (outputTensor.type != TensorType.float32) {
        throw FormatException(
          'Unexpected classifier output type: ${outputTensor.type}; '
          'expected float32.',
        );
      }

      success = true;

      return SunoAudioClassifier._(
        interpreter: interpreter,
        labels: labels,
        confidenceThreshold: threshold.toDouble(),
      );
    } finally {
      if (!success) {
        interpreter.close();
      }
    }
  }

  /// Runs the classifier on one YAMNet embedding.
  ///
  /// The current exported classifier expects exactly one embedding containing
  /// 1,024 float values.
  SunoClassification classifyEmbedding(List<double> embedding) {
    if (_closed) {
      throw StateError('SunoAudioClassifier has already been closed.');
    }

    if (embedding.length != expectedEmbeddingSize) {
      throw ArgumentError.value(
        embedding.length,
        'embedding.length',
        'Expected exactly $expectedEmbeddingSize values.',
      );
    }

    for (final value in embedding) {
      if (!value.isFinite) {
        throw ArgumentError(
          'Embedding contains a non-finite value: $value.',
        );
      }
    }

    final input = <List<double>>[
      List<double>.from(embedding),
    ];

    final output = <List<double>>[
      List<double>.filled(expectedClassCount, 0.0),
    ];

    _interpreter.run(input, output);

    final scores = output[0];

    for (final score in scores) {
      if (!score.isFinite || score < 0 || score > 1) {
        throw StateError(
          'Classifier returned an invalid probability: $score',
        );
      }
    }

    var bestIndex = 0;

    for (var index = 1; index < scores.length; index++) {
      if (scores[index] > scores[bestIndex]) {
        bestIndex = index;
      }
    }

    final bestConfidence = scores[bestIndex];

    // Preserve the agreed ML contract: predictions below 0.30 confidence
    // fall back to ambient_safe. Risk scoring remains outside this adapter.
    final label = bestConfidence < confidenceThreshold
        ? 'ambient_safe'
        : _labels[bestIndex];

    return SunoClassification(
      label: label,
      confidence: bestConfidence,
      index: bestIndex,
    );
  }

  void close() {
    if (_closed) {
      return;
    }

    _closed = true;
    _interpreter.close();
  }

  static bool _sameLabels(
    List<String> actual,
    List<String> expected,
  ) {
    if (actual.length != expected.length) {
      return false;
    }

    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }

    return true;
  }
}
