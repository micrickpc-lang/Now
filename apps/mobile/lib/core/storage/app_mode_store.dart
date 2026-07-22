import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppModeStore {
  AppModeStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _demoModeKey = 'app.demo_mode';
  final FlutterSecureStorage _storage;

  Future<bool?> readDemoMode() async {
    final value = await _storage.read(key: _demoModeKey);
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  Future<void> writeDemoMode(bool enabled) =>
      _storage.write(key: _demoModeKey, value: enabled.toString());
}

final appModeStoreProvider = Provider<AppModeStore>((_) => AppModeStore());
