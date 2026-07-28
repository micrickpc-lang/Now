import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../map/domain/map_models.dart';
import '../domain/exact_location_models.dart';

abstract interface class ExactLocationShareRepository {
  Future<List<ExactLocationShare>> mine();
  Future<List<VisibleExactLocation>> visible();
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
  });
  Future<ExactLocationShare> update(
    String shareId, {
    required GeoPoint point,
    String? label,
    bool? backgroundUpdatesEnabled,
  });
  Future<void> revoke(String shareId);
}

class ApiExactLocationShareRepository implements ExactLocationShareRepository {
  ApiExactLocationShareRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ExactLocationShare>> mine() async {
    final response = await _api.dio.get<List<dynamic>>('/location-shares/mine');
    return response.data!
        .map(
          (row) => ExactLocationShare.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<VisibleExactLocation>> visible() async {
    final response = await _api.dio.get<List<dynamic>>(
      '/location-shares/visible',
    );
    return response.data!
        .map(
          (row) => VisibleExactLocation.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

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
  }) async {
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/location-shares',
      data: {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'audience': audience.apiValue,
        'expiryMode': expiryMode.apiValue,
        'explicitConsent': explicitConsent,
        'backgroundUpdatesEnabled': backgroundUpdatesEnabled,
        if (recipientIds.isNotEmpty) 'recipientIds': recipientIds,
        ?circleId: circleId,
        ?roomId: roomId,
        if (label != null && label.isNotEmpty) 'label': label,
      },
    );
    return ExactLocationShare.fromJson(response.data!);
  }

  @override
  Future<ExactLocationShare> update(
    String shareId, {
    required GeoPoint point,
    String? label,
    bool? backgroundUpdatesEnabled,
  }) async {
    final response = await _api.dio.patch<Map<String, dynamic>>(
      '/location-shares/$shareId',
      data: {
        'latitude': point.latitude,
        'longitude': point.longitude,
        if (label != null && label.isNotEmpty) 'label': label,
        ?backgroundUpdatesEnabled: backgroundUpdatesEnabled,
      },
    );
    return ExactLocationShare.fromJson(response.data!);
  }

  @override
  Future<void> revoke(String shareId) =>
      _api.dio.delete<void>('/location-shares/$shareId');
}

final exactLocationShareRepositoryProvider =
    Provider<ExactLocationShareRepository>(
      (ref) => ApiExactLocationShareRepository(ref.watch(apiClientProvider)),
    );

final myExactLocationSharesProvider = FutureProvider<List<ExactLocationShare>>(
  (ref) => ref.watch(exactLocationShareRepositoryProvider).mine(),
);

final visibleExactLocationsProvider =
    FutureProvider<List<VisibleExactLocation>>(
      (ref) => ref.watch(exactLocationShareRepositoryProvider).visible(),
    );
