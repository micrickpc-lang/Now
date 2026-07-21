import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_cache.dart';
import '../domain/signal.dart';

class SignalsRepository {
  SignalsRepository(this._api, this._cache);
  final ApiClient _api;
  final LocalCache _cache;

  Future<List<SignalModel>> feed() async {
    try {
      final response = await _api.dio.get<List<dynamic>>('/signals/feed');
      final rows = response.data!.cast<Map<String, dynamic>>();
      for (final row in rows) {
        await _cache.cacheSignal(
          row['id'] as String,
          jsonEncode(row),
          DateTime.parse(row['expiresAt'] as String),
        );
      }
      return rows.map(SignalModel.fromJson).toList();
    } catch (_) {
      final cached = await _cache.cachedSignals();
      if (cached.isEmpty) rethrow;
      return cached
          .map(
            (row) =>
                SignalModel.fromJson(jsonDecode(row) as Map<String, dynamic>),
          )
          .toList();
    }
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/signals',
      data: payload,
    );
    return response.data!;
  }

  Future<void> join(String id) => _api.dio.post<void>('/signals/$id/join');
}

final signalsRepositoryProvider = Provider<SignalsRepository>(
  (ref) => SignalsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localCacheProvider),
  ),
);

class SignalFeedController extends AsyncNotifier<List<SignalModel>> {
  @override
  Future<List<SignalModel>> build() =>
      ref.watch(signalsRepositoryProvider).feed();
  Future<void> refresh() async => state = await AsyncValue.guard(
    () => ref.read(signalsRepositoryProvider).feed(),
  );
}

final signalFeedProvider =
    AsyncNotifierProvider<SignalFeedController, List<SignalModel>>(
      SignalFeedController.new,
    );
