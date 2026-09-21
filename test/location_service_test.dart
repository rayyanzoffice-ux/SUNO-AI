import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:suno_ai/backend/location/location_service.dart';

void main() {
  late GeolocatorPlatform original;
  late _LocationPlatform platform;
  late LocationService service;
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
    service = LocationService();
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  test(
    'GPS preserves the platform timestamp and high accuracy settings',
    () async {
      final result = await service.currentLocation();
      expect(result?.latitude, 33.68);
      expect(result?.longitude, 73.04);
      expect(result?.capturedAt, platform.position.timestamp);
      expect(service.status, LocationStatus.ready);
      expect(platform.settings?.accuracy, LocationAccuracy.high);
      expect(platform.settings?.timeLimit, const Duration(seconds: 10));
      expect(platform.prompts, 0);
    },
  );

  test('disabled location never requests permission or a fix', () async {
    platform.enabled = false;
    expect(await service.currentLocation(), isNull);
    expect(service.status, LocationStatus.disabled);
    expect(platform.prompts, 0);
    expect(platform.fixes, 0);
  });

  test('noninteractive denial never prompts', () async {
    platform.permission = LocationPermission.denied;
    expect(await service.currentLocation(requestPermission: false), isNull);
    expect(service.status, LocationStatus.denied);
    expect(platform.prompts, 0);
    expect(platform.fixes, 0);
  });

  test('interactive grant requests permission once', () async {
    platform.permission = LocationPermission.denied;
    platform.requestedPermission = LocationPermission.whileInUse;
    expect(await service.currentLocation(), isNotNull);
    expect(await service.currentLocation(requestPermission: false), isNotNull);
    expect(platform.prompts, 1);
  });

  test(
    'denial and permanent denial are explicit without background prompts',
    () async {
      for (final permission in [
        LocationPermission.denied,
        LocationPermission.deniedForever,
      ]) {
        platform.permission = permission;
        expect(await service.currentLocation(), isNull);
        expect(service.status, LocationStatus.denied);
      }
      expect(platform.prompts, 1);
      expect(platform.fixes, 0);
    },
  );

  test('timeout clears a previously successful result', () async {
    expect(await service.currentLocation(), isNotNull);
    platform.error = TimeoutException('No GPS fix');
    expect(await service.currentLocation(), isNull);
    expect(service.status, LocationStatus.timedOut);
  });

  test('invalid coordinates and platform errors are unavailable', () async {
    for (final latitude in [double.nan, double.infinity, 91.0]) {
      platform.position = makePosition(latitude: latitude);
      expect(await service.currentLocation(), isNull);
      expect(service.status, LocationStatus.unavailable);
    }
    platform.error = StateError('GPS unavailable');
    expect(await service.currentLocation(), isNull);
    expect(service.status, LocationStatus.unavailable);
  });
}

Position makePosition({double latitude = 33.68}) => Position(
  latitude: latitude,
  longitude: 73.04,
  timestamp: DateTime.utc(2026, 9, 21),
  accuracy: 4,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.denied;
  Position position = makePosition();
  Object? error;
  LocationSettings? settings;
  int prompts = 0;
  int fixes = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return permission = requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    fixes++;
    settings = locationSettings;
    if (error != null) throw error!;
    return position;
  }
}
