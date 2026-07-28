import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class ActiveRoom {
  const ActiveRoom({
    required this.id,
    required this.title,
    required this.expiresAt,
  });

  factory ActiveRoom.fromJson(Map<String, dynamic> json) => ActiveRoom(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Temporary room',
    expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
  );

  final String id;
  final String title;
  final DateTime expiresAt;
}

class RoomLocationShare {
  const RoomLocationShare({
    required this.id,
    required this.ownerId,
    required this.expiresAt,
    this.latitude,
    this.longitude,
    this.label,
  });

  factory RoomLocationShare.fromJson(Map<String, dynamic> json) {
    final value = json['value'] is Map
        ? Map<String, dynamic>.from(json['value'] as Map)
        : const <String, dynamic>{};
    return RoomLocationShare(
      id: json['id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      latitude: (value['latitude'] as num?)?.toDouble(),
      longitude: (value['longitude'] as num?)?.toDouble(),
      label: value['label']?.toString(),
    );
  }

  final String id;
  final String ownerId;
  final DateTime expiresAt;
  final double? latitude;
  final double? longitude;
  final String? label;
}

abstract interface class RoomLocationShareRepository {
  Future<RoomLocationShare> createLocationShare(
    String id, {
    required double latitude,
    required double longitude,
    String? label,
  });

  Future<void> revokeLocationShare(String id);
}

class RoomsRepository implements RoomLocationShareRepository {
  RoomsRepository(this._api);
  final ApiClient _api;
  Future<Map<String, dynamic>> room(String id) async =>
      (await _api.dio.get<Map<String, dynamic>>('/rooms/$id')).data!;
  Future<List<ActiveRoom>> activeRooms() async {
    final response = await _api.dio.get<List<dynamic>>('/rooms/active');
    return response.data!
        .map(
          (row) => ActiveRoom.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> messages(String id) async =>
      (await _api.dio.get<List<dynamic>>(
        '/rooms/$id/messages',
      )).data!.cast<Map<String, dynamic>>();
  Future<void> send(String id, String body) =>
      _api.dio.post<void>('/rooms/$id/messages', data: {'body': body});
  Future<void> leave(String id) => _api.dio.post<void>('/rooms/$id/leave');

  /// Exact room locations are deliberately fetched from the dedicated endpoint.
  /// `GET /rooms/:id` must never be used as a source of location shares.
  Future<List<RoomLocationShare>> locationShares(String id) async {
    final data = await _api.dio.get<List<dynamic>>('/rooms/$id/location-share');
    return data.data!
        .map(
          (row) =>
              RoomLocationShare.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<RoomLocationShare> createLocationShare(
    String id, {
    required double latitude,
    required double longitude,
    String? label,
  }) => _api.dio
      .post<Map<String, dynamic>>(
        '/rooms/$id/location-share',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'ttlMinutes': 30,
          'explicitConsent': true,
          if (label != null && label.isNotEmpty) 'label': label,
        },
      )
      .then(
        (response) => RoomLocationShare.fromJson(
          Map<String, dynamic>.from(response.data ?? const <String, dynamic>{}),
        ),
      );

  @override
  Future<void> revokeLocationShare(String id) =>
      _api.dio.delete<void>('/rooms/$id/location-share');
}

final roomsRepositoryProvider = Provider<RoomsRepository>(
  (ref) => RoomsRepository(ref.watch(apiClientProvider)),
);

final activeRoomsProvider = FutureProvider<List<ActiveRoom>>(
  (ref) => ref.watch(roomsRepositoryProvider).activeRooms(),
);
