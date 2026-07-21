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

  Future<void> clearSensitive() async {
    await _ready;
    await database.executor.runCustom('DELETE FROM outbox');
    await database.executor.runCustom('DELETE FROM cached_signals');
  }

  Future<void> close() => database.executor.close();
}

final localCacheProvider = Provider<LocalCache>((_) => LocalCache());

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
