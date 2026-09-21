import 'dart:typed_data';

import 'audio_waveform.dart';

class AudioPreprocessor {
  AudioPreprocessor({
    this.inputSampleRate = 44100,
    this.outputSampleRate = 16000,
    this.frameLength = 15360,
    this.frameHop = 7680,
  }) : assert(inputSampleRate > 0 && outputSampleRate > 0),
       assert(frameHop > 0 && frameHop <= frameLength);

  final int inputSampleRate;
  final int outputSampleRate;
  final int frameLength;
  final int frameHop;
  final List<double> _buffer = [];
  int? _lowByte;
  double? _previousSample;
  int _inputIndex = -1;
  int _outputIndex = 0;

  List<AudioWaveform> feed(Uint8List rawBytes) {
    for (final byte in rawBytes) {
      final low = _lowByte;
      if (low == null) {
        _lowByte = byte;
        continue;
      }
      _lowByte = null;
      final value = low | (byte << 8);
      final sample = (value >= 32768 ? value - 65536 : value) / 32768.0;
      _inputIndex++;
      // Integer phase and the previous sample survive arbitrary PCM chunk boundaries.
      while (_outputIndex * inputSampleRate <= _inputIndex * outputSampleRate) {
        final position = _outputIndex * inputSampleRate / outputSampleRate;
        final fraction = position - (_inputIndex - 1);
        final previous = _previousSample ?? sample;
        _buffer.add(previous + (sample - previous) * fraction);
        _outputIndex++;
      }
      _previousSample = sample;
    }
    final frames = <AudioWaveform>[];
    while (_buffer.length >= frameLength) {
      frames.add(
        AudioWaveform(
          samples: List<double>.from(_buffer.take(frameLength)),
          sampleRate: outputSampleRate,
          capturedAt: DateTime.now(),
        ),
      );
      _buffer.removeRange(0, frameHop);
    }
    return frames;
  }

  void reset() {
    _buffer.clear();
    _lowByte = null;
    _previousSample = null;
    _inputIndex = -1;
    _outputIndex = 0;
  }
}
