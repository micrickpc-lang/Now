import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/cache_file_protection.dart';
import 'cache_cipher.dart';

class LocalCache {
  LocalCache({CacheCipher? cipher})
    : database = DatabaseConnection.delayed(
        Future(() async {
          final directory = await getApplicationSupportDirectory();
          final file = File(p.join(directory.path, 'seychas_cache.sqlite'));
          if (!await file.exists()) await file.create(recursive: true);
          await CacheFileProtection.excludeFromBackups(file.path);
          return DatabaseConnection(NativeDatabase.createInBackground(file));
        }),
      ),
      _cipher = cipher ?? SecureCacheCipher() {
    _ready = _initialize();
  }

  LocalCache.forTest(QueryExecutor executor, {CacheCipher? cipher})
    : database = DatabaseConnection.delayed(
        Future.value(DatabaseConnection(executor)),
      ),
      _cipher = cipher ?? InMemoryCacheCipher() {
    _ready = _initialize();
  }

  final DatabaseConnection database;
  final CacheCipher _cipher;
  late final Future<void> _ready;

  Future<void> _initialize() async {
    await database.executor.ensureOpen(const _CacheExecutorUser());
    await database.executor.runCustom('PRAGMA secure_delete = ON');
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
    try {
      await _migrateLegacyPayloads();
    } catch (_) {
      // A replaced or corrupted Keychain/Keystore entry cannot decrypt cache.
      // Delete only local replicas and continue with a new, empty cache.
      await _clearSensitiveRows();
    }
  }

  Future<void> cacheSignal(
    String id,
    String payload,
    DateTime expiresAt,
  ) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO cached_signals(id,payload,expires_at) VALUES(?,?,?)',
      [id, await _cipher.encrypt(payload), expiresAt.millisecondsSinceEpoch],
    );
  }

  Future<List<String>> cachedSignals() async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT payload FROM cached_signals WHERE expires_at > ? ORDER BY expires_at',
      [DateTime.now().millisecondsSinceEpoch],
    );
    return _decryptRows(rows, 'payload');
  }

  Future<void> cacheConversation(
    String id,
    String payload, {
    DateTime? updatedAt,
  }) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO cached_conversations(id,payload,updated_at) VALUES(?,?,?)',
      [
        id,
        await _cipher.encrypt(payload),
        (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<String>> cachedConversations() async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT payload FROM cached_conversations ORDER BY updated_at DESC, id DESC',
      const [],
    );
    return _decryptRows(rows, 'payload');
  }

  Future<String?> cachedConversation(String id) async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT payload FROM cached_conversations WHERE id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : _decrypt(rows.single['payload']! as String);
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
      [
        id,
        conversationId,
        await _cipher.encrypt(payload),
        createdAt.millisecondsSinceEpoch,
      ],
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
    return _decryptRows(rows, 'payload');
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
      [
        conversationId,
        await _cipher.encrypt(body),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<String?> draft(String conversationId) async {
    await _ready;
    final rows = await database.executor.runSelect(
      'SELECT body FROM conversation_drafts WHERE conversation_id = ? LIMIT 1',
      [conversationId],
    );
    return rows.isEmpty ? null : _decrypt(rows.single['body']! as String);
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
      [
        id,
        method,
        path,
        await _cipher.encrypt(payload),
        DateTime.now().millisecondsSinceEpoch,
      ],
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
    return Future.wait(
      rows.map(
        (row) async => OutboxEntry(
          id: row['id']! as String,
          method: row['method']! as String,
          path: row['path']! as String,
          payload: await _decrypt(row['payload']! as String),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at']! as int,
          ),
        ),
      ),
    );
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
    return rows.isEmpty ? null : _decrypt(rows.single['value']! as String);
  }

  Future<void> writeSetting(String key, String value) async {
    await _ready;
    await database.executor.runInsert(
      'INSERT OR REPLACE INTO app_settings(key,value) VALUES(?,?)',
      [key, await _cipher.encrypt(value)],
    );
  }

  Future<void> clearSensitive() async {
    await _ready;
    await _clearSensitiveRows();
    await _cipher.deleteKey();
  }

  Future<void> _clearSensitiveRows() async {
    await database.executor.runCustom('DELETE FROM outbox');
    await database.executor.runCustom('DELETE FROM cached_signals');
    await database.executor.runCustom('DELETE FROM cached_messages');
    await database.executor.runCustom('DELETE FROM cached_conversations');
    await database.executor.runCustom('DELETE FROM conversation_drafts');
    await database.executor.runCustom('DELETE FROM app_settings');
  }

  Future<List<String>> _decryptRows(
    List<Map<String, Object?>> rows,
    String column,
  ) async => Future.wait(rows.map((row) => _decrypt(row[column]! as String)));

  Future<String> _decrypt(String value) => _cipher.decrypt(value);

  Future<void> _migrateLegacyPayloads() async {
    await _migrateLegacyColumn('cached_signals', 'id', 'payload');
    await _migrateLegacyColumn('outbox', 'id', 'payload');
    await _migrateLegacyColumn('cached_conversations', 'id', 'payload');
    await _migrateLegacyColumn('cached_messages', 'id', 'payload');
    await _migrateLegacyColumn(
      'conversation_drafts',
      'conversation_id',
      'body',
    );
    await _migrateLegacyColumn('app_settings', 'key', 'value');
  }

  Future<void> _migrateLegacyColumn(
    String table,
    String idColumn,
    String valueColumn,
  ) async {
    final rows = await database.executor.runSelect(
      'SELECT $idColumn, $valueColumn FROM $table',
      const [],
    );
    for (final row in rows) {
      final value = row[valueColumn]! as String;
      if (value.startsWith('aesgcm:v1:')) {
        await _cipher.decrypt(value);
        continue;
      }
      await database.executor.runUpdate(
        'UPDATE $table SET $valueColumn = ? WHERE $idColumn = ?',
        [await _cipher.encrypt(value), row[idColumn]],
      );
    }
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
