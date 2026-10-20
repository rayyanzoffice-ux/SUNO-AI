import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../persistence/app_storage.dart';

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
    this.isCached = false,
  });

  final double latitude;
  final double longitude;
  final String? locationText;
  final DateTime capturedAt;

  /// True when this snapshot came from the persisted cache rather than a GPS
  /// fix taken just now, so an alert can say how old it is instead of
  /// presenting a stale position as current.
  final bool isCached;

  Duration get age => DateTime.now().difference(capturedAt);

  String get description =>
      locationText ??
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'locationText': locationText,
    'capturedAt': capturedAt.toIso8601String(),
  };

  static LocationSnapshot? fromJson(Map<Object?, Object?>? json) {
    if (json == null) return null;
    final lat = json['latitude'];
    final lon = json['longitude'];
    final captured = json['capturedAt'];
    if (lat is! num || lon is! num || captured is! String) return null;
    final parsed = DateTime.tryParse(captured);
    if (parsed == null) return null;
    return LocationSnapshot(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      locationText: json['locationText'] as String?,
      capturedAt: parsed,
      isCached: true,
    );
  }
}

class LocationService {
  LocationStatus status = LocationStatus.idle;
  static const _cacheKey = 'last_known';

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
    Duration timeLimit = const Duration(seconds: 10),
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
        timeLimit: timeLimit,
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        status = LocationStatus.unavailable;
        return null;
      }
      status = LocationStatus.ready;
      final snapshot = LocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        capturedAt: position.timestamp,
      );
      unawaited(_cache(snapshot));
      return snapshot;
    } on TimeoutException {
      status = LocationStatus.timedOut;
      return null;
    } catch (_) {
      status = LocationStatus.unavailable;
      return null;
    }
  }

  /// Writes a fresh fix to the cache. Never throws — a failed cache write must
  /// not break the detection or alert flow around it.
  Future<void> _cache(LocationSnapshot snapshot) async {
    try {
      await locationCacheBox.put(_cacheKey, snapshot.toJson());
    } catch (_) {
      // Best-effort only: the in-memory snapshot already handed to the caller
      // is what matters for the current alert.
    }
  }

  /// Reads the last cached fix without touching GPS hardware. Returns null if
  /// nothing has ever been cached.
  LocationSnapshot? readCached() {
    try {
      return LocationSnapshot.fromJson(
        locationCacheBox.get(_cacheKey)?.cast<Object?, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Driven every 30 minutes while Live monitoring is active, purely to keep
  /// the cache warm. Deliberately does not touch [status], so it never fights
  /// the UI's own "locating…" indicator for a user-triggered request.
  Future<void> refreshCacheQuietly() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        return;
      }
      await _cache(
        LocationSnapshot(
          latitude: position.latitude,
          longitude: position.longitude,
          capturedAt: position.timestamp,
        ),
      );
    } catch (_) {
      // Offline or GPS briefly unavailable — any existing cache entry is left
      // untouched and is still usable.
    }
  }

  /// What an escalating alert should use: a quick fresh fix if the GPS radio
  /// can produce one in time, otherwise the last cached fix with
  /// [LocationSnapshot.isCached] set so the payload can carry its age.
  Future<LocationSnapshot?> bestEffortLocation({
    Duration freshTimeout = const Duration(seconds: 6),
  }) async {
    final fresh = await currentLocation(
      requestPermission: false,
      timeLimit: freshTimeout,
    );
    if (fresh != null) return fresh;
    return readCached();
  }
}
