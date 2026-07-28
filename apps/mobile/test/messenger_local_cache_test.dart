import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/storage/cache_cipher.dart';
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

  test(
    'sensitive cache payloads are AES-GCM envelopes, not plaintext',
    () async {
      final cache = LocalCache.forTest(NativeDatabase.memory());
      const secret = 'private message that must not reach sqlite';
      await cache.cacheMessage(
        id: 'message',
        conversationId: 'chat',
        payload: secret,
        createdAt: DateTime.now(),
      );
      await cache.saveDraft('chat', secret);
      await cache.enqueue(
        id: 'queued',
        method: 'POST',
        path: '/conversations/chat/messages',
        payload: secret,
      );

      for (final table in [
        'cached_messages',
        'conversation_drafts',
        'outbox',
      ]) {
        final column = table == 'conversation_drafts' ? 'body' : 'payload';
        final row =
            (await cache.database.executor.runSelect(
                  'SELECT $column FROM $table LIMIT 1',
                  const [],
                )).single[column]!
                as String;
        expect(row, startsWith('aesgcm:v1:'));
        expect(row, isNot(contains(secret)));
      }
      expect((await cache.cachedMessages('chat')).single, secret);
      expect(await cache.draft('chat'), secret);
      expect((await cache.outbox()).single.payload, secret);
      await cache.close();
    },
  );

  test('legacy plaintext rows migrate without data loss', () async {
    final executor = NativeDatabase.memory();
    await executor.ensureOpen(const _TestExecutorUser());
    await executor.runCustom(
      'CREATE TABLE cached_messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, payload TEXT NOT NULL, created_at INTEGER NOT NULL)',
    );
    await executor.runInsert(
      'INSERT INTO cached_messages(id, conversation_id, payload, created_at) VALUES (?, ?, ?, ?)',
      ['legacy', 'chat', 'before migration', 1],
    );
    final cache = LocalCache.forTest(executor);

    expect(await cache.cachedMessages('chat'), ['before migration']);
    final row =
        (await cache.database.executor.runSelect(
              'SELECT payload FROM cached_messages WHERE id = ?',
              ['legacy'],
            )).single['payload']!
            as String;
    expect(row, startsWith('aesgcm:v1:'));
    await cache.close();
  });

  test(
    'lost encryption key clears local replicas without exposing payloads',
    () async {
      final executor = NativeDatabase.memory();
      final cipher = InMemoryCacheCipher();
      final firstCache = LocalCache.forTest(executor, cipher: cipher);
      await firstCache.cacheMessage(
        id: 'message',
        conversationId: 'chat',
        payload: 'unrecoverable after key loss',
        createdAt: DateTime.now(),
      );
      await cipher.deleteKey();

      final recoveredCache = LocalCache.forTest(executor, cipher: cipher);
      expect(await recoveredCache.cachedMessages('chat'), isEmpty);
      await recoveredCache.close();
    },
  );
}

class _TestExecutorUser implements QueryExecutorUser {
  const _TestExecutorUser();

  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
