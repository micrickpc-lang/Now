import 'package:flutter/services.dart';

abstract final class CacheFileProtection {
  static const _channel = MethodChannel('ru.seychas/storage');

  static Future<void> excludeFromBackups(String databasePath) async {
    try {
      await _channel.invokeMethod<void>('excludeFromBackups', databasePath);
    } on MissingPluginException {
      // Android backups are disabled in the manifest.
    }
  }
}
