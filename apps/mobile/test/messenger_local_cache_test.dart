import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/storage/local_cache.dart';

void main() {
  test('messenger cache persists drafts, pages and outbox', () async {
    final cache = LocalCache.forTest(NativeDatabase.memory());
    final now = DateTime.now();
    await cache.cacheConversation('chat', '{"id":"chat"}');
    for (var index = 0; index < 4; index++) {
      await cache.cacheMessage(
        id: 'message-$index',
        conversationId: 'chat',
        payload: '{"id":"message-$index"}',
        createdAt: now.subtract(Duration(minutes: index)),
      );
    }
    await cache.saveDraft('chat', 'Черновик');
    await cache.enqueue(
      id: 'client-message',
      method: 'POST',
      path: '/conversations/chat/messages',
      payload: '{"text":"Без сети"}',
    );

    expect(await cache.cachedConversation('chat'), '{"id":"chat"}');
    expect(await cache.cachedMessages('chat', limit: 2), hasLength(2));
    expect(await cache.draft('chat'), 'Черновик');
    expect(
      await cache.outbox(path: '/conversations/chat/messages'),
      hasLength(1),
    );

    await cache.removeOutbox('client-message');
    expect(await cache.outbox(), isEmpty);
    await cache.close();
  });
}
