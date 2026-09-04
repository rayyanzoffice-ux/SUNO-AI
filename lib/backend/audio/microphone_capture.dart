import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_preprocessor.dart';
import 'audio_waveform.dart';
import 'microphone_permission.dart';

/// Thrown by [MicrophoneCapture.start] when the microphone permission is
/// not granted. Callers should surface [message] to the user — live
/// detection must fail honestly rather than silently doing nothing.
class MicrophonePermissionException implements Exception {
  const MicrophonePermissionException(
    this.message, {
    required this.permanentlyDenied,
  });

  final String message;
  final bool permanentlyDenied;

  @override
  String toString() => 'MicrophonePermissionException: $message';
}

/// Thrown when the platform recorder fails to start for a reason other
/// than permissions (e.g. the microphone is already in use).
class MicrophoneCaptureException implements Exception {
  const MicrophoneCaptureException(this.message);

  final String message;

  @override
  String toString() => 'MicrophoneCaptureException: $message';
}

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

  /// Starts capture. Throws [MicrophonePermissionException] if the
  /// microphone permission is denied, or [MicrophoneCaptureException] if
  /// the platform recorder fails to start for any other reason.
  Future<void> start() async {
    if (_active) return;

    final permission = await MicrophonePermission.ensureGranted();
    if (permission != MicPermissionStatus.granted) {
      throw MicrophonePermissionException(
        permission == MicPermissionStatus.permanentlyDenied
            ? 'Microphone permission is permanently denied. Enable it '
              'from system Settings to use Live Mode.'
            : 'Microphone permission is required for Live Mode.',
        permanentlyDenied:
            permission == MicPermissionStatus.permanentlyDenied,
      );
    }

    _controller ??= StreamController<AudioWaveform>.broadcast();
    _preprocessor.reset();

    try {
      final pcmStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 44100,
          numChannels: 1,
          bitRate: 128000,
        ),
      );
      _active = true;

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
    } catch (e) {
      _active = false;
      throw MicrophoneCaptureException('Failed to start microphone: $e');
    }
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

