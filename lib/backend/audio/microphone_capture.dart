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

    final permission = await MicrophonePermission.ensureGranted(
      requestPermission: false,
    );
    if (permission != MicPermissionStatus.granted) {
      throw MicrophonePermissionException(
        permission == MicPermissionStatus.permanentlyDenied
            ? 'Microphone permission is permanently denied. Enable it '
                  'from system Settings to use Live Mode.'
            : 'Microphone permission is required for Live Mode.',
        permanentlyDenied: permission == MicPermissionStatus.permanentlyDenied,
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
        onError: (Object err, StackTrace stack) {
          final ctrl = _controller;
          if (ctrl != null && !ctrl.isClosed) ctrl.addError(err, stack);
        },
        onDone: () {
          final ctrl = _controller;
          if (_active && ctrl != null && !ctrl.isClosed) {
            ctrl.addError(
              const MicrophoneCaptureException(
                'Microphone stream ended unexpectedly.',
              ),
            );
          }
          _active = false;
        },
      );
    } catch (e) {
      _active = false;
      throw MicrophoneCaptureException('Failed to start microphone: $e');
    }
  }

  Future<void> stop() async {
    final subscription = _rawSub;
    final wasActive = _active;
    _active = false;
    _rawSub = null;
    try {
      await subscription?.cancel();
    } finally {
      try {
        if (wasActive || subscription != null) await _recorder.stop();
      } finally {
        _preprocessor.reset();
      }
    }
  }

  Future<void> dispose() async {
    try {
      await stop();
    } finally {
      try {
        await _recorder.dispose();
      } finally {
        final controller = _controller;
        _controller = null;
        await controller?.close();
      }
    }
  }
}
