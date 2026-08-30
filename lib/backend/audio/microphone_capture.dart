import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_preprocessor.dart';
import 'audio_waveform.dart';

/// Owns the microphone lifecycle and streams preprocessed [AudioWaveform]
/// windows for downstream inference.
class MicrophoneCapture {
  MicrophoneCapture({AudioPreprocessor? preprocessor})
    : _preprocessor = preprocessor ?? AudioPreprocessor();

  final AudioPreprocessor _preprocessor;
  final AudioRecorder _recorder = AudioRecorder();

  StreamController<AudioWaveform>? _controller;
  StreamSubscription<Uint8List>? _rawSub;
  bool _active = false;

  Stream<AudioWaveform> get waveforms {
    _controller ??= StreamController<AudioWaveform>.broadcast();
    return _controller!.stream;
  }

  bool get isActive => _active;

  Future<void> start() async {
    if (_active) return;
    _controller ??= StreamController<AudioWaveform>.broadcast();
    _preprocessor.reset();
    _active = true;

    final pcmStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
      ),
    );

    _rawSub = pcmStream.listen(
      (chunk) {
        for (final frame in _preprocessor.feed(chunk)) {
          final ctrl = _controller;
          if (ctrl != null && !ctrl.isClosed) ctrl.add(frame);
        }
      },
      onError: (Object err) {
        final ctrl = _controller;
        if (ctrl != null && !ctrl.isClosed) ctrl.addError(err);
      },
    );
  }

  Future<void> stop() async {
    _active = false;
    await _rawSub?.cancel();
    _rawSub = null;
    await _recorder.stop();
    _preprocessor.reset();
  }

  Future<void> dispose() async {
    await stop();
    await _controller?.close();
    _controller = null;
    _recorder.dispose();
  }
}
