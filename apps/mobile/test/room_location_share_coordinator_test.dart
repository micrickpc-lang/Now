import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/location/location_provider.dart';
import 'package:seychas/features/map/domain/map_models.dart';
import 'package:seychas/features/rooms/data/room_location_share_coordinator.dart';
import 'package:seychas/features/rooms/data/rooms_repository.dart';

void main() {
  test(
    'starts GPS only after exact share is created and throttles uploads',
    () async {
      final rooms = _Rooms();
      final location = _Location();
      var now = DateTime.utc(2026, 7, 25, 12);
      final coordinator = RoomLocationShareCoordinator(
        rooms,
        location,
        clock: () => now,
      );

      await coordinator.start(
        'room-1',
        const MapSelectionResult(
          mode: LocationPrivacyMode.exactRoomOnly,
          sourcePoint: GeoPoint(43.7, 7.4),
          label: 'Meeting point',
        ),
      );

      expect(rooms.uploads, hasLength(1));
      expect(location.watchCalls, 1);
      expect(coordinator.activeRoomId, 'room-1');

      location.emit(43.71, 7.41);
      await _flush();
      expect(rooms.uploads, hasLength(1));

      now = now.add(const Duration(seconds: 10));
      location.emit(43.72, 7.42);
      await _flush();
      expect(rooms.uploads, hasLength(2));
      expect(rooms.uploads.last, (
        roomId: 'room-1',
        latitude: 43.72,
        longitude: 7.42,
      ));
    },
  );

  test(
    'stop cancels foreground GPS and best-effort revokes the server share',
    () async {
      final rooms = _Rooms();
      final location = _Location();
      final coordinator = RoomLocationShareCoordinator(rooms, location);
      await coordinator.start(
        'room-1',
        const MapSelectionResult(
          mode: LocationPrivacyMode.exactRoomOnly,
          sourcePoint: GeoPoint(43.7, 7.4),
        ),
      );

      await coordinator.stop();

      expect(location.stopCalls, 1);
      expect(rooms.revokedRoomIds, ['room-1']);
      expect(coordinator.isActive, isFalse);
    },
  );

  test(
    'explicit revoke reports a server failure after GPS is stopped',
    () async {
      final rooms = _Rooms()..failRevoke = true;
      final location = _Location();
      final coordinator = RoomLocationShareCoordinator(rooms, location);
      await coordinator.start(
        'room-1',
        const MapSelectionResult(
          mode: LocationPrivacyMode.exactRoomOnly,
          sourcePoint: GeoPoint(43.7, 7.4),
        ),
      );

      await expectLater(
        coordinator.stop(suppressRevokeErrors: false),
        throwsA(isA<StateError>()),
      );
      expect(location.stopCalls, 1);
      expect(coordinator.isActive, isFalse);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Rooms implements RoomLocationShareRepository {
  final uploads = <({String roomId, double latitude, double longitude})>[];
  final revokedRoomIds = <String>[];
  bool failRevoke = false;

  @override
  Future<RoomLocationShare> createLocationShare(
    String id, {
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    uploads.add((roomId: id, latitude: latitude, longitude: longitude));
    return RoomLocationShare(
      id: 'share-${uploads.length}',
      ownerId: 'me',
      expiresAt: DateTime.utc(2026, 7, 25, 12, 30),
    );
  }

  @override
  Future<void> revokeLocationShare(String id) async {
    revokedRoomIds.add(id);
    if (failRevoke) throw StateError('offline');
  }
}

class _Location implements LocationProvider {
  final _updates = StreamController<DeviceLocation>.broadcast();
  int watchCalls = 0;
  int stopCalls = 0;

  void emit(double latitude, double longitude) => _updates.add(
    DeviceLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: 5,
      timestamp: DateTime.utc(2026, 7, 25, 12),
    ),
  );

  @override
  Stream<DeviceLocation> watchLocationForActiveShare() {
    watchCalls++;
    return _updates.stream;
  }

  @override
  Future<void> stopWatching() async => stopCalls++;

  @override
  Future<LocationPermissionState> checkPermission() async =>
      LocationPermissionState.whileInUsePrecise;

  @override
  Future<DeviceLocation> getCurrentLocation() => Future<DeviceLocation>.error(
    const LocationFailure(LocationFailureCode.unavailable),
  );

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.whileInUsePrecise;
}
