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

  @override
  String toString() =>
      'AudioWaveform(samples: $lengthSamples, '
      'duration: ${durationSeconds.toStringAsFixed(3)}s)';
}
