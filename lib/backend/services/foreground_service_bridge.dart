import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ForegroundServiceBridge {
  const ForegroundServiceBridge._();
  static const _channel = MethodChannel(
    'com.example.suno_ai/monitoring_service',
  );
  static AsyncCallback? onStopRequested;
  static AsyncCallback? onServiceStopped;
  static bool _initialized = false;
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start({
    bool microphoneEnabled = true,
    bool locationEnabled = false,
    String status = 'SUNO is listening',
  }) async {
    if (!_android) return;
    if (!_initialized) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopRequested') await onStopRequested?.call();
        if (call.method == 'serviceStopped') await onServiceStopped?.call();
      });
      _initialized = true;
    }
    try {
      await _channel
          .invokeMethod<void>('start', {
            'microphoneEnabled': microphoneEnabled,
            'locationEnabled': locationEnabled,
            'status': status,
          })
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  static Future<void> updateStatus(String status) async {
    if (_android) {
      await _channel.invokeMethod<void>('updateStatus', {'status': status});
    }
  }

  static Future<void> stop() async {
    if (_android) {
      await _channel
          .invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 15));
    }
  }
}
