import 'package:permission_handler/permission_handler.dart';

/// Wraps the `SEND_SMS` runtime request so the UI gets a plain bool instead of
/// reasoning about raw permission objects. Mirrors `MicrophonePermission`.
class SmsPermission {
  const SmsPermission._();

  /// Requests `SEND_SMS` once if it has not been granted. A `false` result is
  /// not a failure of the alert path — push still works, only the offline
  /// fallback does not.
  static Future<bool> ensureGranted() async {
    final status = await Permission.sms.status;
    if (status.isGranted) return true;
    final result = await Permission.sms.request();
    return result.isGranted;
  }
}
