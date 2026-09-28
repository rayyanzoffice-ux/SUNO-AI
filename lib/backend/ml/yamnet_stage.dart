import 'package:tflite_flutter/tflite_flutter.dart';

import '../audio/audio_waveform.dart';

/// A single 1024-dimensional YAMNet embedding for one audio frame.
class YamNetEmbedding {
  const YamNetEmbedding({required this.embedding, required this.frameIndex});

  final List<double> embedding;
  final int frameIndex;
}

/// Wraps yamnet.tflite and converts a [AudioWaveform] into YAMNet embeddings.
///
/// Model contract for the TF Hub lite model used by SUNO:
///   Input:  [15360] float32 waveform (16 kHz, 0.96 s)
///   Output: [_, 521]  class probabilities (not used here)
///   Output: [_, 1024] embeddings  ← fed to SUNO classifier
///   Output: [_, 64]   internal log-mel spectrogram (not used here)
///
/// The row counts are not something the model file states reliably: TFLite
/// resolves some output shapes only while a run is executing. [embed]
/// therefore measures them from a real run instead of assuming them. The
/// embedding output is located by its 1024-wide last dimension rather than by
/// export order, and every declared output needs a buffer on each run.
class YamNetStage {
  static const _modelAsset = 'assets/ml/yamnet.tflite';
  static const _expectedInputLength = 15360;
  static const _embeddingSize = 1024;

  YamNetStage._({
    required this._interpreter,
    required this._embeddingOutputIndex,
    required this._outputShapes,
  });

  final Interpreter _interpreter;
  final int _embeddingOutputIndex;
  List<List<int>> _outputShapes;
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

      // This model file exposes more than one output tensor (class scores,
      // embeddings, and an internal log-mel spectrogram SUNO doesn't use).
      // Find the 1024-wide embedding output by its shape instead of assuming
      // a fixed index; the other outputs still need buffers on every run.
      final outputTensors = interpreter.getOutputTensors();
      var embeddingIndex = -1;
      for (var i = 0; i < outputTensors.length; i++) {
        final shape = outputTensors[i].shape;
        if (shape.isNotEmpty && shape.last == _embeddingSize) {
          embeddingIndex = i;
          break;
        }
      }
      if (embeddingIndex == -1) {
        throw FormatException(
          'YAMNet model has no output tensor with a $_embeddingSize-wide '
          'last dimension. Output shapes found: '
          '${outputTensors.map((t) => t.shape).toList()}',
        );
      }

      // A starting point only: TFLite resolves some of these shapes while a
      // run executes, so embed() re-measures them if a run rejects them.
      final outputShapes = <List<int>>[
        for (final tensor in outputTensors) tensor.shape.toList(),
      ];

      success = true;
      return YamNetStage._(
        interpreter: interpreter,
        embeddingOutputIndex: embeddingIndex,
        outputShapes: outputShapes,
      );
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
    try {
      return _run(input);
    } on ArgumentError {
      // Rejecting a buffer happens after inference, so this is the point where
      // TFLite knows its real output shapes. Measure them and run again; later
      // frames use the measured shapes and never reach this catch.
      _measureOutputShapes();
      return _run(input);
    }
  }

  /// One inference pass, with a buffer per output tensor.
  ///
  /// runForMultipleInputs() copies into every output the model declares and
  /// null-checks each entry of the map, so SUNO's unused outputs still need a
  /// correctly sized buffer even though only the embedding is read.
  List<YamNetEmbedding> _run(List<double> input) {
    final outputs = <int, Object>{};
    for (var i = 0; i < _outputShapes.length; i++) {
      outputs[i] = _buildBuffer(_outputShapes[i]);
    }
    _interpreter.runForMultipleInputs([input], outputs);
    return _embeddingsFrom(outputs[_embeddingOutputIndex]);
  }

  void _measureOutputShapes() {
    _outputShapes = [
      for (final tensor in _interpreter.getOutputTensors())
        tensor.shape.toList(),
    ];
  }

  static List<YamNetEmbedding> _embeddingsFrom(Object? embeddingTensor) {
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
      frames.add(
        YamNetEmbedding(embedding: List<double>.from(row), frameIndex: fi),
      );
    }
    return frames;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _interpreter.close();
  }

  static Object _buildBuffer(List<int> shape) {
    final safeShape = shape
        .map((dimension) => dimension < 0 ? 1 : dimension)
        .toList();
    if (safeShape.length == 1) {
      return List<double>.filled(safeShape[0], 0.0);
    }
    if (safeShape.length == 2) {
      return List<List<double>>.generate(
        safeShape[0],
        (_) => List<double>.filled(safeShape[1], 0.0),
      );
    }
    return List<double>.filled(safeShape.reduce((a, b) => a * b), 0.0);
  }
}
