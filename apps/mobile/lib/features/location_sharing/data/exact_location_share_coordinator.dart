import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_provider.dart';
import '../../map/domain/map_models.dart';
import '../domain/exact_location_models.dart';
import 'exact_location_shares_repository.dart';

/// Keeps foreground GPS updates scoped to explicit, server-created shares.
class ExactLocationShareCoordinator {
  ExactLocationShareCoordinator(
    this._shares,
    this._location, {
    DateTime Function()? clock,
    this.uploadInterval = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now;

  final ExactLocationShareRepository _shares;
  final LocationProvider _location;
  final DateTime Function() _clock;
  final Duration uploadInterval;
  final Map<String, StreamSubscription<DeviceLocation>> _subscriptions = {};
  final Map<String, DateTime> _lastUploadAt = {};

  Set<String> get activeShareIds => Set.unmodifiable(_subscriptions.keys);
  bool isActive(String shareId) => _subscriptions.containsKey(shareId);

  Future<void> start(ExactLocationShare share) async {
    if (isActive(share.id)) await stop(share.id, revoke: false);
    _lastUploadAt[share.id] = _clock();
    _subscriptions[share.id] = _location.watchLocationForActiveShare().listen(
      (location) => unawaited(_uploadIfDue(share.id, location)),
      onError: (_, __) {},
    );
  }

  Future<void> _uploadIfDue(String shareId, DeviceLocation location) async {
    if (!isActive(shareId)) return;
    final previous = _lastUploadAt[shareId];
    if (previous != null && _clock().difference(previous) < uploadInterval) {
      return;
    }
    _lastUploadAt[shareId] = _clock();
    try {
      await _shares.update(
        shareId,
        point: GeoPoint(location.latitude, location.longitude),
      );
    } catch (_) {
      // The server owns expiry/revocation. A later foreground location retries.
    }
  }

  Future<void> stop(
    String shareId, {
    bool revoke = true,
    bool suppressRevokeErrors = true,
  }) async {
    final subscription = _subscriptions.remove(shareId);
    _lastUploadAt.remove(shareId);
    try {
      await subscription?.cancel();
    } finally {
      if (_subscriptions.isEmpty) {
        await _location.stopWatching();
      }
    }
    if (!revoke) return;
    try {
      await _shares.revoke(shareId);
    } catch (_) {
      if (!suppressRevokeErrors) rethrow;
    }
  }

  Future<void> stopAll({bool revoke = true}) async {
    for (final shareId in activeShareIds) {
      await stop(shareId, revoke: revoke);
    }
  }
}

final exactLocationShareCoordinatorProvider =
    Provider<ExactLocationShareCoordinator>((ref) {
      final coordinator = ExactLocationShareCoordinator(
        ref.watch(exactLocationShareRepositoryProvider),
        ref.watch(locationProviderProvider),
      );
      ref.onDispose(() => unawaited(coordinator.stopAll()));
      return coordinator;
    });
