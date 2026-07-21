import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _accessKey = 'session.access';
  static const _refreshKey = 'session.refresh';
  static const _installationKey = 'device.installation';

  Future<String?> access() => _storage.read(key: _accessKey);
  Future<String?> refresh() => _storage.read(key: _refreshKey);

  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> clear() => _storage.deleteAll();

  Future<String?> installationId() => _storage.read(key: _installationKey);
  Future<void> writeInstallationId(String value) =>
      _storage.write(key: _installationKey, value: value);
}

final tokenStoreProvider = Provider<TokenStore>(
  (_) => TokenStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  ),
);
