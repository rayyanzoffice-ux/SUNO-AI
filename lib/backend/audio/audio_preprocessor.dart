import 'dart:typed_data';
import 'audio_waveform.dart';

/// Accepts raw PCM data from the device microphone and produces normalized
/// [AudioWaveform] windows suitable for YAMNet inference.
///
/// Input : Int16 PCM bytes (little-endian) at [inputSampleRate].
/// Output: float32 mono frames at 16 kHz, normalized to [-1, +1],
///         sized to [frameLength] samples with [frameHop] sample stride.
class AudioPreprocessor {
  AudioPreprocessor({
    this.inputSampleRate = 44100,
    this.outputSampleRate = 16000,
    this.frameLength = 15360, // 0.96 s at 16 kHz
    this.frameHop = 7680,     // 0.48 s at 16 kHz
  });

  final int inputSampleRate;
  final int outputSampleRate;
  final int frameLength;
  final int frameHop;

  final List<double> _buffer = [];

  /// Feed a raw PCM Int16 LE chunk from the microphone.
  /// Returns zero or more complete waveform windows.
  List<AudioWaveform> feed(Uint8List rawBytes) {
    if (rawBytes.length < 2) return const [];
    final resampled = _resampleToTarget(rawBytes);
    _buffer.addAll(resampled);

    final frames = <AudioWaveform>[];
    while (_buffer.length >= frameLength) {
      frames.add(AudioWaveform(
        samples: List<double>.from(_buffer.take(frameLength)),
        sampleRate: outputSampleRate,
        capturedAt: DateTime.now(),
      ));
      _buffer.removeRange(0, frameHop);
    }
    return frames;
  }

  void reset() => _buffer.clear();

  List<double> _resampleToTarget(Uint8List rawBytes) {
    final byteData = rawBytes.buffer
        .asByteData(rawBytes.offsetInBytes, rawBytes.lengthInBytes);
    final sampleCount = rawBytes.length ~/ 2;
    final int16Samples = List<double>.generate(sampleCount, (i) {
      final raw = byteData.getInt16(i * 2, Endian.little);
      return raw / 32768.0;
    });

    if (inputSampleRate == outputSampleRate) return int16Samples;

    final ratio = inputSampleRate / outputSampleRate;
    final outputLength = (sampleCount / ratio).floor();
    return List<double>.generate(outputLength, (i) {
      final srcPos = i * ratio;
      final srcIdx = srcPos.floor();
      final frac = srcPos - srcIdx;
      if (srcIdx + 1 >= sampleCount) return int16Samples[srcIdx];
      return int16Samples[srcIdx] * (1 - frac) +
             int16Samples[srcIdx + 1] * frac;
    });
  }
}
