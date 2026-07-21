import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class RoomsRepository {
  RoomsRepository(this._api);
  final ApiClient _api;
  Future<Map<String, dynamic>> room(String id) async =>
      (await _api.dio.get<Map<String, dynamic>>('/rooms/$id')).data!;
  Future<List<Map<String, dynamic>>> messages(String id) async =>
      (await _api.dio.get<List<dynamic>>(
        '/rooms/$id/messages',
      )).data!.cast<Map<String, dynamic>>();
  Future<void> send(String id, String body) =>
      _api.dio.post<void>('/rooms/$id/messages', data: {'body': body});
  Future<void> leave(String id) => _api.dio.post<void>('/rooms/$id/leave');
  Future<void> share(
    String id, {
    required double latitude,
    required double longitude,
  }) => _api.dio.post<void>(
    '/rooms/$id/location-share',
    data: {
      'latitude': latitude,
      'longitude': longitude,
      'ttlMinutes': 30,
      'explicitConsent': true,
    },
  );
  Future<void> revoke(String id) =>
      _api.dio.delete<void>('/rooms/$id/location-share');
}

final roomsRepositoryProvider = Provider<RoomsRepository>(
  (ref) => RoomsRepository(ref.watch(apiClientProvider)),
);
