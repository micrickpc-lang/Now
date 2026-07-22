import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seychas/core/network/api_client.dart';
import 'package:seychas/core/network/realtime_client.dart';
import 'package:seychas/core/storage/local_cache.dart';
import 'package:seychas/core/storage/token_store.dart';
import 'package:seychas/features/chats/data/chats_repository.dart';

class _MockTokenStore extends Mock implements TokenStore {}

class _MockRealtimeCoordinator extends Mock implements RealtimeCoordinator {}

void main() {
  test('loads every cursor page before retaining cached chats', () async {
    final cache = LocalCache.forTest(NativeDatabase.memory());
    final dio = Dio();
    final api = ApiClient(dio, _MockTokenStore());
    final cursors = <String?>[];
    addTearDown(() async {
      await api.dispose();
      await cache.close();
    });

    await cache.writeSetting('account.current_user_id', 'viewer');
    await _seedPendingChat(cache, 'chat-on-second-page');
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final cursor = options.queryParameters['cursor'] as String?;
          cursors.add(cursor);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: cursor == null
                  ? {
                      'items': [_conversation('chat-on-first-page', 2)],
                      'nextCursor': 'page-2',
                    }
                  : {
                      'items': [_conversation('chat-on-second-page', 1)],
                      'nextCursor': null,
                    },
            ),
          );
        },
      ),
    );
    final repository = ChatsRepository(
      api,
      cache,
      _MockRealtimeCoordinator(),
      false,
    );

    final page = await repository.conversations();

    expect(cursors, [null, 'page-2']);
    expect(page.items.map((conversation) => conversation.id), [
      'chat-on-first-page',
      'chat-on-second-page',
    ]);
    expect(await cache.draft('chat-on-second-page'), 'pending draft');
    expect(await cache.cachedMessages('chat-on-second-page'), hasLength(1));
    expect(
      await cache.outbox(path: '/conversations/chat-on-second-page/messages'),
      hasLength(1),
    );
  });

  test('failed later page never triggers destructive retention', () async {
    final cache = LocalCache.forTest(NativeDatabase.memory());
    final dio = Dio();
    final api = ApiClient(dio, _MockTokenStore());
    addTearDown(() async {
      await api.dispose();
      await cache.close();
    });

    await cache.writeSetting('account.current_user_id', 'viewer');
    await _seedPendingChat(cache, 'cached-pending-chat');
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.queryParameters['cursor'] == null) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'items': [_conversation('new-first-page-chat', 2)],
                  'nextCursor': 'page-2',
                },
              ),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: StateError('network failed on page 2'),
            ),
          );
        },
      ),
    );
    final repository = ChatsRepository(
      api,
      cache,
      _MockRealtimeCoordinator(),
      false,
    );

    final fallback = await repository.conversations();

    expect(fallback.items.map((conversation) => conversation.id), [
      'cached-pending-chat',
    ]);
    expect(await cache.draft('cached-pending-chat'), 'pending draft');
    expect(await cache.cachedMessages('cached-pending-chat'), hasLength(1));
    expect(
      await cache.outbox(path: '/conversations/cached-pending-chat/messages'),
      hasLength(1),
    );
  });
}

Future<void> _seedPendingChat(LocalCache cache, String id) async {
  await cache.cacheConversation(id, jsonEncode(_conversation(id, 1)));
  await cache.cacheMessage(
    id: 'pending-$id',
    conversationId: id,
    payload: '{"id":"pending-$id"}',
    createdAt: DateTime.utc(2026, 7, 22),
  );
  await cache.saveDraft(id, 'pending draft');
  await cache.enqueue(
    id: 'outbox-$id',
    method: 'POST',
    path: '/conversations/$id/messages',
    payload: '{"text":"offline"}',
  );
}

Map<String, dynamic> _conversation(String id, int minute) => {
  'id': id,
  'type': 'DIRECT',
  'createdAt': DateTime.utc(2026, 7, 22).toIso8601String(),
  'updatedAt': DateTime.utc(2026, 7, 22, 0, minute).toIso8601String(),
  'members': const <Map<String, dynamic>>[],
};
