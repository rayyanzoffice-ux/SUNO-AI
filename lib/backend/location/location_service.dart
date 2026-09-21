import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationStatus {
  idle,
  locating,
  ready,
  denied,
  disabled,
  timedOut,
  unavailable,
}

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

  String get description =>
      locationText ??
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

class LocationService {
  LocationStatus status = LocationStatus.idle;

  Future<bool> hasPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<LocationSnapshot?> currentLocation({
    bool requestPermission = true,
  }) async {
    status = LocationStatus.locating;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        status = LocationStatus.disabled;
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        status = LocationStatus.denied;
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        status = LocationStatus.unavailable;
        return null;
      }
      status = LocationStatus.ready;
      return LocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        capturedAt: position.timestamp,
      );
    } on TimeoutException {
      status = LocationStatus.timedOut;
      return null;
    } catch (_) {
      status = LocationStatus.unavailable;
      return null;
    }
  }
}
