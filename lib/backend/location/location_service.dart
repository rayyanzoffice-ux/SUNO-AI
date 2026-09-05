import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

/// Location snapshot attached to a detection event.
class LocationSnapshot {
  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    this.locationText,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final String? locationText;
  final DateTime capturedAt;
}

/// Provides a single best-effort location fix. Returns null when permission
/// is denied or the device cannot produce a fix — never returns fixed demo
/// coordinates in live mode.
class LocationService {
  Future<LocationSnapshot?> currentLocation() async {
    bool serviceEnabled;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return null;
    }
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    // Android requires background location to be requested as a separate,
    // second prompt after foreground location has already been granted.
    if (permission == LocationPermission.whileInUse) {
      final backgroundStatus =
          await handler.Permission.locationAlways.request();
      if (backgroundStatus.isGranted) {
        permission = await Geolocator.checkPermission();
      }
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return LocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
