import 'package:flutter/services.dart';

/// Bridges to the native Android foreground service that keeps SUNO's
/// microphone monitoring alive when the app is backgrounded.
///
/// No-ops safely when the native implementation is unavailable (e.g. in
/// widget tests, or on platforms other than Android) so callers never
/// need special-case handling — starting/stopping the service is always
/// best-effort and never blocks the in-app detection pipeline.
class ForegroundServiceBridge {
  const ForegroundServiceBridge._();

  static const _channel = MethodChannel(
    'com.example.suno_ai/monitoring_service',
  );

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('start');
    } on MissingPluginException {
      // No native implementation available (e.g. widget tests) — ignore.
    } on PlatformException {
      // Non-fatal: live detection continues in-app even if the persistent
      // notification/service could not be started.
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on MissingPluginException {
      // No native implementation available — ignore.
    } on PlatformException {
      // Non-fatal.
    }
  }
}
