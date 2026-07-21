import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/storage/local_cache.dart';

void main() {
  test(
    'offline cache returns only live signals and stores no location columns',
    () async {
      final cache = LocalCache.forTest(NativeDatabase.memory());
      await cache.cacheSignal(
        'live',
        '{"id":"live"}',
        DateTime.now().add(const Duration(minutes: 5)),
      );
      await cache.cacheSignal(
        'expired',
        '{"id":"expired"}',
        DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(await cache.cachedSignals(), ['{"id":"live"}']);
      final columns = await cache.database.executor.runSelect(
        'PRAGMA table_info(cached_signals)',
        const [],
      );
      expect(
        columns.map((row) => row['name']),
        isNot(containsAll(['latitude', 'longitude', 'coordinates'])),
      );
      await cache.close();
    },
  );
}
