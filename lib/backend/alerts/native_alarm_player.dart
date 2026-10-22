import 'package:flutter/services.dart';

/// Plays the bundled alarm through Android's alarm audio stream. Unlike a
/// notification sound, this keeps playing while SUNO is in the background or
/// its task has been swiped away, because the countdown's foreground service
/// keeps the process alive.
class NativeAlarmPlayer {
  static const _channel = MethodChannel('com.example.suno_ai/alarm');

  /// [duration] stops the loop on the native side as well; a throttled Dart
  /// isolate must not be able to leave the alarm ringing past the countdown.
  /// Returns false when no tune could be started, so the caller can vibrate
  /// instead of leaving the person with a silent alarm.
  Future<bool> start({Duration? duration}) async {
    try {
      final started = await _channel.invokeMethod<bool>('start', {
        if (duration != null) 'durationMs': duration.inMilliseconds,
      });
      return started ?? false;
    } catch (_) {
      // A platform without the bridge (widget tests, future iOS) relies on the
      // caller's vibration fallback.
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
