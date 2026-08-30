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
/// Model contract for the TF Hub lite model used by SUNO:
///   Input  [0]: [15360] float32 waveform (16 kHz, 0.96 s)
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
      interpreter.resizeInputTensor(0, [_expectedInputLength]);
      interpreter.allocateTensors();
      final inputShape = interpreter.getInputTensor(0).shape;
      if (inputShape.length != 1 || inputShape[0] != _expectedInputLength) {
        throw FormatException(
          'YAMNet input shape mismatch: $inputShape; '
          'expected [$_expectedInputLength].',
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

    final input = List<double>.from(waveform.samples);
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

    if (embeddingTensor.length == _embeddingSize &&
        embeddingTensor.every((value) => value is num)) {
      return [
        YamNetEmbedding(
          embedding: List<double>.from(embeddingTensor),
          frameIndex: 0,
        ),
      ];
    }

    final frames = <YamNetEmbedding>[];
    for (var fi = 0; fi < embeddingTensor.length; fi++) {
      final row = embeddingTensor[fi];
      if (row is! List || row.length != _embeddingSize) {
        throw StateError('Unexpected embedding row shape at frame $fi.');
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
    final safeShape = shape.map((dimension) => dimension < 0 ? 1 : dimension).toList();
    if (safeShape.length == 1) {
      return List<double>.filled(safeShape[0], 0.0);
    }
    if (safeShape.length == 2) {
      return List<List<double>>.generate(
        safeShape[0], (_) => List<double>.filled(safeShape[1], 0.0));
    }
    return List<double>.filled(safeShape.reduce((a, b) => a * b), 0.0);
  }
}
