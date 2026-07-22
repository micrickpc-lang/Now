import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalCache {
  LocalCache()
    : database = DatabaseConnection.delayed(
        Future(() async {
          final directory = await getApplicationSupportDirectory();
          final file = File(p.join(directory.path, 'seychas_cache.sqlite'));
          return DatabaseConnection(NativeDatabase.createInBackground(file));
        }),
      ) {
    _ready = _initialize();
  }

  LocalCache.forTest(QueryExecutor executor)
    : database = DatabaseConnection.delayed(
        Future.value(DatabaseConnection(executor)),
      ) {
    _ready = _initialize();
  }

  final DatabaseConnection database;
  late final Future<void> _ready;

  Future<void> _initialize() async {
    await database.executor.ensureOpen(const _CacheExecutorUser());
    await database.executor.runCustom(
      'CREATE TABLE IF NOT EXISTS cached_signals (id TEXT PRIMARY KEY, payload TEXT NOT NULL, expires_at INTEGER NOT NULL)',
    );
    await database.executor.runCustom(
      'CREATE TABLE IF NOT EXISTS outbox (id TEXT PRIMARY KEY, method TEXT NOT NULL, path TEXT NOT NULL, payload TEXT NOT NULL, created_at INTEGER NOT NULL)',
    );
    await database.executor.runCustom(
      'CREATE TABLE IF NOT EXISTS cached_conversations (id TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await database.executor.runCustom(
      'CREATE TABLE IF NOT EXISTS cached_messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, payload TEXT NOT NULL, created_at INTEGER NOT NULL)',
    );
    await database.executor.runCustom(
      'CREATE INDEX IF NOT EXISTS cached_messages_page ON cached_messages(conversation_id, created_at DESC, id DESC)',
    );
    await database.executor.runCustom(
      'CREATE TABLE IF NOT EXISTS conversation_drafts (conversation_id TEXT PRIMARY KEY, body TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await database.executor.runCustom(
      'CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  Future<void> cacheSignal(
    String id,
    String payload,
    DateTime expiresAt,
  ) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO cached_signals(id,payload,expires_at) VALUES(?,?,?)',
      [id, payload, expiresAt.millisecondsSinceEpoch],
    );
  }

  Future<List<String>> cachedSignals() async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT payload FROM cached_signals WHERE expires_at > ? ORDER BY expires_at',
      [DateTime.now().millisecondsSinceEpoch],
    );
    return rows.map((row) => row['payload']! as String).toList();
  }

  Future<void> cacheConversation(
    String id,
    String payload, {
    DateTime? updatedAt,
  }) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO cached_conversations(id,payload,updated_at) VALUES(?,?,?)',
      [id, payload, (updatedAt ?? DateTime.now()).millisecondsSinceEpoch],
    );
  }

  Future<List<String>> cachedConversations() async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT payload FROM cached_conversations ORDER BY updated_at DESC, id DESC',
      const [],
    );
    return rows.map((row) => row['payload']! as String).toList();
  }

  Future<String?> cachedConversation(String id) async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT payload FROM cached_conversations WHERE id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : rows.single['payload']! as String;
  }

  Future<void> retainConversations(Set<String> ids) async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT id FROM cached_conversations',
      const [],
    );
    for (final row in rows) {
      final id = row['id']! as String;
      if (ids.contains(id)) continue;
      await database.executor.runDelete(
        'DELETE FROM cached_messages WHERE conversation_id = ?',
        [id],
      );
      await database.executor.runDelete(
        'DELETE FROM conversation_drafts WHERE conversation_id = ?',
        [id],
      );
      await database.executor.runDelete('DELETE FROM outbox WHERE path = ?', [
        '/conversations/$id/messages',
      ]);
      await database.executor.runDelete(
        'DELETE FROM cached_conversations WHERE id = ?',
        [id],
      );
    }
  }

  Future<void> cacheMessage({
    required String id,
    required String conversationId,
    required String payload,
    required DateTime createdAt,
  }) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO cached_messages(id,conversation_id,payload,created_at) VALUES(?,?,?,?)',
      [id, conversationId, payload, createdAt.millisecondsSinceEpoch],
    );
  }

  Future<List<String>> cachedMessages(
    String conversationId, {
    int limit = 40,
    int? beforeEpochMs,
  }) async {
    await _ready;
    final rows = beforeEpochMs == null
        ? await database.executor.runSelect(
            'SELECT payload FROM cached_messages WHERE conversation_id = ? ORDER BY created_at DESC, id DESC LIMIT ?',
            [conversationId, limit],
          )
        : await database.executor.runSelect(
            'SELECT payload FROM cached_messages WHERE conversation_id = ? AND created_at < ? ORDER BY created_at DESC, id DESC LIMIT ?',
            [conversationId, beforeEpochMs, limit],
          );
    return rows.map((row) => row['payload']! as String).toList();
  }

  Future<void> removeCachedMessage(String id) async {
    await _ready;
    await database.executor.runDelete(
      'DELETE FROM cached_messages WHERE id = ?',
      [id],
    );
  }

  Future<void> saveDraft(String conversationId, String body) async {
    await _ready;
    if (body.trim().isEmpty) {
      await database.executor.runDelete(
        'DELETE FROM conversation_drafts WHERE conversation_id = ?',
        [conversationId],
      );
      return;
    }
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO conversation_drafts(conversation_id,body,updated_at) VALUES(?,?,?)',
      [conversationId, body, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<String?> draft(String conversationId) async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT body FROM conversation_drafts WHERE conversation_id = ? LIMIT 1',
      [conversationId],
    );
    return rows.isEmpty ? null : rows.single['body']! as String;
  }

  Future<void> enqueue({
    required String id,
    required String method,
    required String path,
    required String payload,
  }) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO outbox(id,method,path,payload,created_at) VALUES(?,?,?,?,?)',
      [id, method, path, payload, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<List<OutboxEntry>> outbox({String? path}) async {
    await _ready;
    final rows = path == null
        ? await database.executor.runSelect(
            'SELECT id,method,path,payload,created_at FROM outbox ORDER BY created_at',
            const [],
          )
        : await database.executor.runSelect(
            'SELECT id,method,path,payload,created_at FROM outbox WHERE path = ? ORDER BY created_at',
            [path],
          );
    return rows
        .map(
          (row) => OutboxEntry(
            id: row['id']! as String,
            method: row['method']! as String,
            path: row['path']! as String,
            payload: row['payload']! as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at']! as int,
            ),
          ),
        )
        .toList();
  }

  Future<void> removeOutbox(String id) async {
    await _ready;
    await database.executor.runDelete('DELETE FROM outbox WHERE id = ?', [id]);
  }

  Future<String?> setting(String key) async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1',
      [key],
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> writeSetting(String key, String value) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO app_settings(key,value) VALUES(?,?)',
      [key, value],
    );
  }

  Future<void> clearSensitive() async {
    await _ready;
    await database.executor.runCustom('DELETE FROM outbox');
    await database.executor.runCustom('DELETE FROM cached_signals');
    await database.executor.runCustom('DELETE FROM cached_messages');
    await database.executor.runCustom('DELETE FROM cached_conversations');
    await database.executor.runCustom('DELETE FROM conversation_drafts');
    await database.executor.runCustom(
      "DELETE FROM app_settings WHERE key LIKE 'demo.%'",
    );
    await database.executor.runCustom(
      "DELETE FROM app_settings WHERE key LIKE 'account.%'",
    );
  }

  Future<void> close() => database.executor.close();
}

final localCacheProvider = Provider<LocalCache>((ref) {
  final cache = LocalCache();
  ref.onDispose(() => unawaited(cache.close()));
  return cache;
});

class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.method,
    required this.path,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String method;
  final String path;
  final String payload;
  final DateTime createdAt;
}

class _CacheExecutorUser implements QueryExecutorUser {
  const _CacheExecutorUser();
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
