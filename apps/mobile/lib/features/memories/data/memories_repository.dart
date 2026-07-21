import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class MemoryModel {
  const MemoryModel({
    required this.id,
    required this.title,
    required this.category,
    required this.occurredAt,
    required this.theme,
  });
  final String id, title, category, theme;
  final DateTime occurredAt;
  factory MemoryModel.fromJson(Map<String, dynamic> json) => MemoryModel(
    id: json['id'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    occurredAt: DateTime.parse(json['occurredAt'] as String).toLocal(),
    theme: json['theme'] as String,
  );
}

class MemoriesRepository {
  MemoriesRepository(this._api);
  final ApiClient _api;
  Future<List<MemoryModel>> list() async => (await _api.dio.get<List<dynamic>>(
    '/memories',
  )).data!.cast<Map<String, dynamic>>().map(MemoryModel.fromJson).toList();
}

final memoriesRepositoryProvider = Provider<MemoriesRepository>(
  (ref) => MemoriesRepository(ref.watch(apiClientProvider)),
);
final memoriesProvider = FutureProvider<List<MemoryModel>>(
  (ref) => ref.watch(memoriesRepositoryProvider).list(),
);
