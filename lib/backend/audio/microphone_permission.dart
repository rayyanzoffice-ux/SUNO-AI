import 'package:permission_handler/permission_handler.dart';

/// Result of requesting the microphone permission required for Live Mode.
enum MicPermissionStatus { granted, denied, permanentlyDenied }

/// Wraps permission_handler so callers get a small, testable enum instead
/// of reasoning about raw platform permission objects.
class MicrophonePermission {
  const MicrophonePermission._();

  static Future<MicPermissionStatus> ensureGranted() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return MicPermissionStatus.granted;

    final result = await Permission.microphone.request();
    if (result.isGranted) return MicPermissionStatus.granted;
    if (result.isPermanentlyDenied) {
      return MicPermissionStatus.permanentlyDenied;
    }
    return MicPermissionStatus.denied;
  }
}
