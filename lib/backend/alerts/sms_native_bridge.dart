import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin bridge to Android's native `SmsManager`. SMS is Android-only by OS
/// policy (iOS does not allow silent, programmatic SMS sending), and this repo
/// ships Android only, so that is not a gap for the finale.
class SmsNativeBridge {
  const SmsNativeBridge._();

  static const _channel = MethodChannel('com.example.suno_ai/sms');

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> hasPermission() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sends one SMS.
  ///
  /// Returns true only when Android's SMS_SENT broadcast reports success for
  /// the whole message. `false` (never throws) covers missing permission, no
  /// SIM, no balance, no signal, platform not supported, or a native
  /// exception — none of which are proof the contact received anything.
  static Future<bool> send({
    required String phoneNumber,
    required String message,
  }) async {
    if (!_android) return false;
    try {
      final result = await _channel
          .invokeMethod<bool>('send', {
            'phone': phoneNumber,
            'message': message,
          })
          // Native waits 6s for SMS_SENT; leave room for channel overhead.
          .timeout(const Duration(seconds: 9));
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
