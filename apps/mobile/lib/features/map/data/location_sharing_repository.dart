import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

enum LocationAudience { friends, selected }

enum LocationPrecision { approximate, exact }

class FriendLocation {
  const FriendLocation({
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.precision,
    required this.expiresAt,
    this.emoji,
  });

  factory FriendLocation.fromJson(Map<String, dynamic> json) {
    final owner = (json['owner'] as Map?)?.cast<String, dynamic>() ?? json;
    final profile = (owner['profile'] as Map?)?.cast<String, dynamic>();
    return FriendLocation(
      userId: (json['ownerId'] ?? owner['id']).toString(),
      name: (owner['displayName'] ?? profile?['displayName'] ?? 'Friend')
          .toString(),
      emoji: (owner['emoji'] ?? profile?['emoji'])?.toString(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      precision: (json['precision']?.toString().toUpperCase() == 'EXACT')
          ? LocationPrecision.exact
          : LocationPrecision.approximate,
      expiresAt: DateTime.parse(json['expiresAt'].toString()).toLocal(),
    );
  }

  final String userId;
  final String name;
  final String? emoji;
  final double latitude;
  final double longitude;
  final LocationPrecision precision;
  final DateTime expiresAt;
}

class LocationShare {
  const LocationShare({
    required this.id,
    required this.audience,
    required this.precision,
    required this.expiresAt,
  });

  factory LocationShare.fromJson(Map<String, dynamic> json) => LocationShare(
    id: json['id'].toString(),
    audience: json['audience']?.toString().toUpperCase() == 'SELECTED'
        ? LocationAudience.selected
        : LocationAudience.friends,
    precision: json['precision']?.toString().toUpperCase() == 'EXACT'
        ? LocationPrecision.exact
        : LocationPrecision.approximate,
    expiresAt: DateTime.parse(json['expiresAt'].toString()).toLocal(),
  );

  final String id;
  final LocationAudience audience;
  final LocationPrecision precision;
  final DateTime expiresAt;
}

class LocationSharingRepository {
  LocationSharingRepository(this._api);

  final ApiClient _api;

  Future<List<FriendLocation>> friendLocations() async {
    final response = await _api.dio.get<dynamic>('/map/friends');
    final body = response.data;
    final rows = body is List
        ? body
        : (body as Map<String, dynamic>)['markers'] as List<dynamic>? ??
              const [];
    return rows
        .whereType<Map>()
        .map((row) => FriendLocation.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<LocationShare>> activeShares() async {
    final response = await _api.dio.get<dynamic>('/location-shares');
    final body = response.data;
    final rows = body is List
        ? body
        : (body as Map<String, dynamic>)['items'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map>()
        .map((row) => LocationShare.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> updateLocation({
    required double latitude,
    required double longitude,
  }) => _api.dio.put<void>(
    '/locations/me',
    data: {'latitude': latitude, 'longitude': longitude},
  );

  Future<LocationShare> createShare({
    required LocationAudience audience,
    required LocationPrecision precision,
    required Duration ttl,
    required bool explicitExactConsent,
    List<String> recipientIds = const [],
  }) async {
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/location-shares',
      data: {
        'audience': audience == LocationAudience.friends
            ? 'FRIENDS'
            : 'SELECTED',
        'precision': precision == LocationPrecision.exact
            ? 'EXACT'
            : 'APPROXIMATE',
        'ttlMinutes': ttl.inMinutes,
        'explicitConsent': explicitExactConsent,
        if (audience == LocationAudience.selected) 'recipientIds': recipientIds,
      },
    );
    return LocationShare.fromJson(response.data!);
  }

  Future<void> revokeShare(String shareId) =>
      _api.dio.delete<void>('/location-shares/$shareId');
}

final locationSharingRepositoryProvider = Provider<LocationSharingRepository>(
  (ref) => LocationSharingRepository(ref.watch(apiClientProvider)),
);

final friendLocationsProvider = FutureProvider<List<FriendLocation>>(
  (ref) => ref.watch(locationSharingRepositoryProvider).friendLocations(),
);

final activeLocationSharesProvider = FutureProvider<List<LocationShare>>(
  (ref) => ref.watch(locationSharingRepositoryProvider).activeShares(),
);
