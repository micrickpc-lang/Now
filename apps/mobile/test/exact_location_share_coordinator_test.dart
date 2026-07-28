import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/location/location_provider.dart';
import 'package:seychas/features/location_sharing/data/exact_location_share_coordinator.dart';
import 'package:seychas/features/location_sharing/data/exact_location_shares_repository.dart';
import 'package:seychas/features/location_sharing/domain/exact_location_models.dart';
import 'package:seychas/features/map/domain/map_models.dart';

void main() {
  test(
    'uploads foreground coordinates no more often than every five seconds',
    () async {
      final repository = _Repository();
      final location = _Location();
      var now = DateTime.utc(2026, 7, 28, 12);
      final coordinator = ExactLocationShareCoordinator(
        repository,
        location,
        clock: () => now,
      );

      await coordinator.start(_share());
      expect(location.watchCalls, 1);
      expect(repository.updates, isEmpty);

      location.emit(43.71, 7.41);
      await _flush();
      expect(repository.updates, isEmpty);

      now = now.add(const Duration(seconds: 5));
      location.emit(43.72, 7.42);
      await _flush();
      expect(repository.updates, [
        (shareId: 'share-1', latitude: 43.72, longitude: 7.42),
      ]);
    },
  );

  test(
    'revoke stops GPS before asking the server to delete the share',
    () async {
      final repository = _Repository();
      final location = _Location();
      final coordinator = ExactLocationShareCoordinator(repository, location);
      await coordinator.start(_share());

      await coordinator.stop('share-1', suppressRevokeErrors: false);

      expect(location.stopCalls, 1);
      expect(repository.revokedIds, ['share-1']);
      expect(coordinator.activeShareIds, isEmpty);
    },
  );
}

ExactLocationShare _share() => ExactLocationShare(
  id: 'share-1',
  audience: ExactLocationAudience.selectedFriends,
  expiryMode: ExactLocationExpiry.thirtyMinutes,
  expiresAt: DateTime.utc(2026, 7, 28, 12, 30),
  updatedAt: DateTime.utc(2026, 7, 28, 12),
  backgroundUpdatesEnabled: false,
  point: const GeoPoint(43.7, 7.4),
  audienceSummary: const ExactLocationAudienceSummary(
    type: 'SELECTED_FRIENDS',
    label: 'Friend',
    viewerCount: 1,
  ),
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Repository implements ExactLocationShareRepository {
  final updates = <({String shareId, double latitude, double longitude})>[];
  final revokedIds = <String>[];

  @override
  Future<ExactLocationShare> create({
    required GeoPoint point,
    required ExactLocationAudience audience,
    required ExactLocationExpiry expiryMode,
    required bool explicitConsent,
    required bool backgroundUpdatesEnabled,
    required List<String> recipientIds,
    String? circleId,
    String? roomId,
    String? label,
  }) async => _share();

  @override
  Future<List<ExactLocationShare>> mine() async => const [];

  @override
  Future<void> revoke(String shareId) async => revokedIds.add(shareId);

  @override
  Future<ExactLocationShare> update(
    String shareId, {
    required GeoPoint point,
    String? label,
    bool? backgroundUpdatesEnabled,
  }) async {
    updates.add((
      shareId: shareId,
      latitude: point.latitude,
      longitude: point.longitude,
    ));
    return _share();
  }

  @override
  Future<List<VisibleExactLocation>> visible() async => const [];
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
      timestamp: DateTime.utc(2026, 7, 28, 12),
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
