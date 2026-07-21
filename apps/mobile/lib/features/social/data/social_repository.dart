import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class FriendModel {
  const FriendModel({required this.id, required this.name, this.emoji});
  final String id;
  final String name;
  final String? emoji;
  factory FriendModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return FriendModel(
      id: json['id'] as String,
      name: profile?['displayName'] as String? ?? 'Друг',
      emoji: profile?['emoji'] as String?,
    );
  }
}

class CircleModel {
  const CircleModel({
    required this.id,
    required this.name,
    this.emoji,
    this.memberCount = 0,
  });
  final String id;
  final String name;
  final String? emoji;
  final int memberCount;
  factory CircleModel.fromJson(Map<String, dynamic> json) => CircleModel(
    id: json['id'] as String,
    name: json['name'] as String,
    emoji: json['emoji'] as String?,
    memberCount: (json['members'] as List<dynamic>?)?.length ?? 0,
  );
}

class SocialRepository {
  SocialRepository(this._api);
  final ApiClient _api;
  Future<List<FriendModel>> friends() async =>
      (await _api.dio.get<List<dynamic>>(
        '/friends',
      )).data!.cast<Map<String, dynamic>>().map(FriendModel.fromJson).toList();
  Future<List<CircleModel>> circles() async =>
      (await _api.dio.get<List<dynamic>>(
        '/circles',
      )).data!.cast<Map<String, dynamic>>().map(CircleModel.fromJson).toList();
  Future<CircleModel> createCircle(String name, List<String> memberIds) async =>
      CircleModel.fromJson(
        (await _api.dio.post<Map<String, dynamic>>(
          '/circles',
          data: {'name': name, 'emoji': '✨', 'memberIds': memberIds},
        )).data!,
      );
  Future<Map<String, dynamic>> invite() async =>
      (await _api.dio.post<Map<String, dynamic>>('/friends/invites')).data!;
}

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => SocialRepository(ref.watch(apiClientProvider)),
);
final friendsProvider = FutureProvider<List<FriendModel>>(
  (ref) => ref.watch(socialRepositoryProvider).friends(),
);
final circlesProvider = FutureProvider<List<CircleModel>>(
  (ref) => ref.watch(socialRepositoryProvider).circles(),
);
