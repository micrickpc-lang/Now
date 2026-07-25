import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;

enum LocationPermissionState {
  notDetermined,
  denied,
  deniedForever,
  restricted,
  whileInUseApproximate,
  whileInUsePrecise,
}

extension LocationPermissionStateX on LocationPermissionState {
  bool get isGranted =>
      this == LocationPermissionState.whileInUseApproximate ||
      this == LocationPermissionState.whileInUsePrecise;

  bool get isPrecise => this == LocationPermissionState.whileInUsePrecise;

  bool get requiresSettings =>
      this == LocationPermissionState.deniedForever ||
      this == LocationPermissionState.restricted;
}

class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.isMocked = false,
  }) : assert(latitude >= -90 && latitude <= 90),
       assert(longitude >= -180 && longitude <= 180),
       assert(accuracyMeters >= 0);

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  final bool isMocked;
}

enum LocationFailureCode {
  permissionDenied,
  permissionDeniedForever,
  restricted,
  serviceDisabled,
  timeout,
  unavailable,
}

class LocationFailure implements Exception {
  const LocationFailure(this.code, [this.cause]);

  final LocationFailureCode code;
  final Object? cause;

  @override
  String toString() => 'LocationFailure(${code.name})';
}

abstract interface class LocationProvider {
  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();
  Future<bool> isLocationServiceEnabled();
  Future<DeviceLocation> getCurrentLocation();
  Stream<DeviceLocation> watchLocationForActiveShare();
  Future<void> stopWatching();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class GeolocatorLocationProvider implements LocationProvider {
  GeolocatorLocationProvider({
    this.positionTimeout = const Duration(seconds: 15),
  });

  final Duration positionTimeout;
  bool _requestedThisSession = false;
  StreamController<DeviceLocation>? _updates;
  StreamSubscription<geo.Position>? _platformSubscription;

  @override
  Future<LocationPermissionState> checkPermission() async {
    final permission = await geo.Geolocator.checkPermission();
    return _mapPermission(permission, requested: _requestedThisSession);
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    _requestedThisSession = true;
    final permission = await geo.Geolocator.requestPermission();
    return _mapPermission(permission, requested: true);
  }

  Future<LocationPermissionState> _mapPermission(
    geo.LocationPermission permission, {
    required bool requested,
  }) async {
    switch (permission) {
      case geo.LocationPermission.denied:
        return requested
            ? LocationPermissionState.denied
            : LocationPermissionState.notDetermined;
      case geo.LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case geo.LocationPermission.unableToDetermine:
        return LocationPermissionState.restricted;
      case geo.LocationPermission.whileInUse:
      case geo.LocationPermission.always:
        final accuracy = await geo.Geolocator.getLocationAccuracy();
        return accuracy == geo.LocationAccuracyStatus.reduced
            ? LocationPermissionState.whileInUseApproximate
            : LocationPermissionState.whileInUsePrecise;
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      geo.Geolocator.isLocationServiceEnabled();

  @override
  Future<DeviceLocation> getCurrentLocation() async {
    await _assertAvailable();
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: _locationSettings(timeLimit: positionTimeout),
      );
      return _fromPosition(position);
    } on TimeoutException catch (error) {
      throw LocationFailure(LocationFailureCode.timeout, error);
    } on geo.LocationServiceDisabledException catch (error) {
      throw LocationFailure(LocationFailureCode.serviceDisabled, error);
    } on geo.PermissionDeniedException catch (error) {
      throw LocationFailure(LocationFailureCode.permissionDenied, error);
    } catch (error) {
      if (error is LocationFailure) rethrow;
      throw LocationFailure(LocationFailureCode.unavailable, error);
    }
  }

  @override
  Stream<DeviceLocation> watchLocationForActiveShare() {
    final active = _updates;
    if (active != null && !active.isClosed) return active.stream;

    final controller = StreamController<DeviceLocation>.broadcast();
    _updates = controller;
    unawaited(_startWatching(controller));
    return controller.stream;
  }

  Future<void> _startWatching(
    StreamController<DeviceLocation> controller,
  ) async {
    try {
      await _assertAvailable();
      if (controller.isClosed || !identical(_updates, controller)) return;
      _platformSubscription =
          geo.Geolocator.getPositionStream(
            locationSettings: _locationSettings(
              timeLimit: const Duration(seconds: 30),
              distanceFilter: 10,
            ),
          ).listen(
            (position) {
              if (!controller.isClosed) controller.add(_fromPosition(position));
            },
            onError: (Object error, StackTrace stack) {
              if (!controller.isClosed) {
                controller.addError(_normalizeError(error), stack);
              }
            },
          );
    } catch (error, stack) {
      if (!controller.isClosed) {
        controller.addError(_normalizeError(error), stack);
      }
    }
  }

  Future<void> _assertAvailable() async {
    if (!await isLocationServiceEnabled()) {
      throw const LocationFailure(LocationFailureCode.serviceDisabled);
    }
    final permission = await checkPermission();
    if (permission.isGranted) return;
    if (permission == LocationPermissionState.deniedForever) {
      throw const LocationFailure(LocationFailureCode.permissionDeniedForever);
    }
    if (permission == LocationPermissionState.restricted) {
      throw const LocationFailure(LocationFailureCode.restricted);
    }
    throw const LocationFailure(LocationFailureCode.permissionDenied);
  }

  geo.LocationSettings _locationSettings({
    Duration? timeLimit,
    int distanceFilter = 0,
  }) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: distanceFilter,
        timeLimit: timeLimit,
        intervalDuration: const Duration(seconds: 5),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: distanceFilter,
        timeLimit: timeLimit,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    }
    return geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: distanceFilter,
      timeLimit: timeLimit,
    );
  }

  DeviceLocation _fromPosition(geo.Position position) => DeviceLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy < 0 ? 0 : position.accuracy,
    timestamp: position.timestamp,
    isMocked: position.isMocked,
  );

  Object _normalizeError(Object error) {
    if (error is LocationFailure) return error;
    if (error is TimeoutException) {
      return LocationFailure(LocationFailureCode.timeout, error);
    }
    if (error is geo.LocationServiceDisabledException) {
      return LocationFailure(LocationFailureCode.serviceDisabled, error);
    }
    if (error is geo.PermissionDeniedException) {
      return LocationFailure(LocationFailureCode.permissionDenied, error);
    }
    return LocationFailure(LocationFailureCode.unavailable, error);
  }

  @override
  Future<void> stopWatching() async {
    final subscription = _platformSubscription;
    _platformSubscription = null;
    await subscription?.cancel();
    final controller = _updates;
    _updates = null;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  @override
  Future<bool> openAppSettings() => geo.Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => geo.Geolocator.openLocationSettings();
}

final locationProviderProvider = Provider<LocationProvider>((ref) {
  final provider = GeolocatorLocationProvider();
  ref.onDispose(() => unawaited(provider.stopWatching()));
  return provider;
});
