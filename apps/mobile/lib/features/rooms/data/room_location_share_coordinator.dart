import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_provider.dart';
import '../../map/domain/map_models.dart';
import 'rooms_repository.dart';

/// Owns the foreground-only GPS subscription for the one room being shared.
/// It is app-scoped so logout can stop and revoke a share even when its screen
/// is no longer mounted.
class RoomLocationShareCoordinator {
  RoomLocationShareCoordinator(
    this._rooms,
    this._location, {
    DateTime Function()? clock,
    this.uploadInterval = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  final RoomLocationShareRepository _rooms;
  final LocationProvider _location;
  final DateTime Function() _clock;
  final Duration uploadInterval;

  StreamSubscription<DeviceLocation>? _subscription;
  String? _activeRoomId;
  DateTime? _lastUploadAt;

  bool get isActive => _activeRoomId != null;
  String? get activeRoomId => _activeRoomId;

  Future<void> start(String roomId, MapSelectionResult selection) async {
    final point = selection.sourcePoint;
    if (selection.mode != LocationPrivacyMode.exactRoomOnly || point == null) {
      throw ArgumentError.value(
        selection,
        'selection',
        'An exact room point is required',
      );
    }

    if (_activeRoomId != null) {
      await stop(revoke: true);
    }

    // The initial user-selected point is uploaded only after consent. The GPS
    // stream is intentionally not opened until this server share exists.
    await _rooms.createLocationShare(
      roomId,
      latitude: point.latitude,
      longitude: point.longitude,
      label: selection.label,
    );
    _activeRoomId = roomId;
    _lastUploadAt = _clock();
    try {
      _subscription = _location.watchLocationForActiveShare().listen(
        (location) => unawaited(_uploadIfDue(roomId, location)),
        onError: (_, __) {},
      );
    } catch (_) {
      await stop(suppressRevokeErrors: true);
      rethrow;
    }
  }

  Future<void> _uploadIfDue(String roomId, DeviceLocation location) async {
    if (_activeRoomId != roomId) return;
    final previous = _lastUploadAt;
    if (previous != null && _clock().difference(previous) < uploadInterval) {
      return;
    }
    _lastUploadAt = _clock();
    try {
      await _rooms.createLocationShare(
        roomId,
        latitude: location.latitude,
        longitude: location.longitude,
      );
    } catch (_) {
      // Keep the active share local. A later GPS update retries the refresh;
      // the server-side TTL remains the final privacy boundary.
    }
  }

  /// Always tears down the device stream before attempting a best-effort
  /// server revoke, including screen disposal and logout.
  Future<void> stop({
    bool revoke = true,
    bool suppressRevokeErrors = true,
  }) async {
    final roomId = _activeRoomId;
    _activeRoomId = null;
    _lastUploadAt = null;
    final subscription = _subscription;
    _subscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // Continue to stop the platform stream and revoke the server share.
    }
    try {
      await _location.stopWatching();
    } catch (_) {
      // A platform teardown failure must not retain the server-side location.
    }
    if (revoke && roomId != null) {
      try {
        await _rooms.revokeLocationShare(roomId);
      } catch (_) {
        if (!suppressRevokeErrors) rethrow;
        // Local GPS must remain stopped even if the network is already gone.
      }
    }
  }
}

final roomLocationShareCoordinatorProvider =
    Provider<RoomLocationShareCoordinator>((ref) {
      final coordinator = RoomLocationShareCoordinator(
        ref.watch(roomsRepositoryProvider),
        ref.watch(locationProviderProvider),
      );
      ref.onDispose(() => unawaited(coordinator.stop()));
      return coordinator;
    });
