import 'package:tflite_flutter/tflite_flutter.dart';

import '../audio/audio_waveform.dart';

/// A single 1024-dimensional YAMNet embedding for one audio frame.
class YamNetEmbedding {
  const YamNetEmbedding({
    required this.embedding,
    required this.frameIndex,
  });

  final List<double> embedding;
  final int frameIndex;
}

/// Wraps yamnet.tflite and converts a [AudioWaveform] into YAMNet embeddings.
///
/// Model contract:
///   Input  [0]: [1, 15360] float32 waveform (16 kHz, 0.96 s)
///   Output [0]: [N_frames, 521] class probabilities (not used here)
///   Output [1]: [N_frames, 1024] embeddings  ← fed to SUNO classifier
class YamNetStage {
  static const _modelAsset = 'assets/ml/yamnet.tflite';
  static const _expectedInputLength = 15360;
  static const _embeddingSize = 1024;

  YamNetStage._({required Interpreter interpreter})
    : _interpreter = interpreter;

  final Interpreter _interpreter;
  bool _closed = false;

  static Future<YamNetStage> load() async {
    final interpreter = await Interpreter.fromAsset(_modelAsset);
    var success = false;
    try {
      interpreter.allocateTensors();
      final inputShape = interpreter.getInputTensor(0).shape;
      if (inputShape.length != 2 ||
          inputShape[0] != 1 ||
          inputShape[1] != _expectedInputLength) {
        throw FormatException(
          'YAMNet input shape mismatch: $inputShape; '
          'expected [1, $_expectedInputLength].',
        );
      }
      success = true;
      return YamNetStage._(interpreter: interpreter);
    } finally {
      if (!success) interpreter.close();
    }
  }

  /// Run YAMNet on one [AudioWaveform] and return per-frame embeddings.
  List<YamNetEmbedding> embed(AudioWaveform waveform) {
    if (_closed) throw StateError('YamNetStage has been closed.');
    if (waveform.samples.length != _expectedInputLength) {
      throw ArgumentError.value(
        waveform.samples.length,
        'waveform.samples.length',
        'Expected exactly $_expectedInputLength samples.',
      );
    }

    final input = [List<double>.from(waveform.samples)];
    final numOutputs = _interpreter.getOutputTensors().length;
    final outputs = <int, Object>{};
    for (var i = 0; i < numOutputs; i++) {
      outputs[i] = _buildBuffer(_interpreter.getOutputTensor(i).shape);
    }
    _interpreter.runForMultipleInputs([input], outputs);

    final embeddingTensor = outputs[1];
    if (embeddingTensor is! List) {
      throw StateError('Unexpected YAMNet embedding tensor type.');
    }

    final frames = <YamNetEmbedding>[];
    for (var fi = 0; fi < embeddingTensor.length; fi++) {
      final row = embeddingTensor[fi] as List;
      if (row.length != _embeddingSize) {
        throw StateError('Unexpected embedding row length: ${row.length}');
      }
      frames.add(YamNetEmbedding(
        embedding: List<double>.from(row),
        frameIndex: fi,
      ));
    }
    return frames;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _interpreter.close();
  }

  static Object _buildBuffer(List<int> shape) {
    if (shape.length == 1) return List<double>.filled(shape[0], 0.0);
    if (shape.length == 2) {
      return List<List<double>>.generate(
        shape[0], (_) => List<double>.filled(shape[1], 0.0));
    }
    return List<double>.filled(shape.reduce((a, b) => a * b), 0.0);
  }
}
