import 'package:geolocator/geolocator.dart';

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

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        capturedAt: DateTime.now(),
      );
    } on Exception {
      return null;
    }
  }
}
