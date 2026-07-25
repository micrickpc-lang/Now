import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/map_models.dart';

class MapsRepository {
  MapsRepository(this._api, this._config);

  final ApiClient _api;
  final AppConfig _config;

  Future<String> loadStyle() async {
    final response = await _api.dio.get<Object>(_config.mapStyleUrl);
    final body = response.data;
    if (body is String) {
      jsonDecode(body);
      return body;
    }
    if (body is Map) return jsonEncode(body);
    throw const FormatException('Map style must be a JSON object');
  }

  Future<List<MapPlace>> search(String query) async {
    final response = await _api.dio.get<List<dynamic>>(
      '/maps/search',
      queryParameters: {'q': query.trim()},
    );
    return response.data!
        .whereType<Map>()
        .map((row) => MapPlace.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<ReverseLocation> reverse(GeoPoint point) async {
    final response = await _api.dio.get<Map<String, dynamic>>(
      '/maps/reverse',
      queryParameters: {'lat': point.latitude, 'lon': point.longitude},
    );
    return ReverseLocation.fromJson(response.data!);
  }

  Future<SafeLocationPreview> createSafeLocation({
    required LocationPrivacyMode mode,
    required GeoPoint point,
    required double accuracyMeters,
  }) async {
    if (!mode.usesSafeLocation) {
      throw ArgumentError.value(mode, 'mode', 'Safe mode is required');
    }
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/maps/approximate-location',
      data: {
        'mode': mode.apiValue,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'accuracyMeters': accuracyMeters.clamp(0, 100000),
      },
    );
    return SafeLocationPreview.fromJson(response.data!);
  }
}

final mapsRepositoryProvider = Provider<MapsRepository>(
  (ref) => MapsRepository(
    ref.watch(apiClientProvider),
    ref.watch(appConfigProvider),
  ),
);
