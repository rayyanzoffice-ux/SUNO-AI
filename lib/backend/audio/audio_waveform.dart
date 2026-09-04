import 'dart:math' as math;

/// A normalized mono audio frame ready for YAMNet inference.
///
/// Values are float32 in approximately -1.0 to +1.0.
/// [sampleRate] is always 16000 Hz for SUNO's pipeline.
class AudioWaveform {
  const AudioWaveform({
    required this.samples,
    required this.sampleRate,
    required this.capturedAt,
  });

  final List<double> samples;
  final int sampleRate;
  final DateTime capturedAt;

  int get lengthSamples => samples.length;
  double get durationSeconds => lengthSamples / sampleRate;

  /// Root-mean-square amplitude of this frame, clamped to [0, 1]. Used to
  /// drive a real waveform visualization from actual microphone input.
  double get rmsAmplitude {
    if (samples.isEmpty) return 0;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / samples.length);
    return rms.clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'AudioWaveform(samples: $lengthSamples, '
      'duration: ${durationSeconds.toStringAsFixed(3)}s)';
}
