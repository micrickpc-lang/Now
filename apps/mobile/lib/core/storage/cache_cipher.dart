import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CacheCipher {
  Future<String> encrypt(String value);
  Future<String> decrypt(String value);
  Future<void> deleteKey();
}

class SecureCacheCipher implements CacheCipher {
  SecureCacheCipher([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _keyName = 'cache.encryption_key.v1';
  static const _prefix = 'aesgcm:v1:';
  static final _algorithm = AesGcm.with256bits();

  final FlutterSecureStorage _storage;
  Future<SecretKey>? _key;

  @override
  Future<String> encrypt(String value) async {
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: await _loadKey(),
    );
    return '$_prefix${base64UrlEncode(secretBox.nonce)}:${base64UrlEncode(secretBox.mac.bytes)}:${base64UrlEncode(secretBox.cipherText)}';
  }

  @override
  Future<String> decrypt(String value) async {
    if (!value.startsWith(_prefix)) {
      // Legacy plaintext is migrated after it is successfully read.
      return value;
    }
    final parts = value.substring(_prefix.length).split(':');
    if (parts.length != 3)
      throw const FormatException('Invalid encrypted cache');
    final clear = await _algorithm.decrypt(
      SecretBox(
        base64Url.decode(parts[2]),
        nonce: base64Url.decode(parts[0]),
        mac: Mac(base64Url.decode(parts[1])),
      ),
      secretKey: await _loadKey(),
    );
    return utf8.decode(clear);
  }

  @override
  Future<void> deleteKey() async {
    _key = null;
    await _storage.delete(key: _keyName);
  }

  Future<SecretKey> _loadKey() {
    return _key ??= _readOrCreateKey();
  }

  Future<SecretKey> _readOrCreateKey() async {
    final stored = await _storage.read(key: _keyName);
    if (stored != null) return SecretKeyData(base64Url.decode(stored));

    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await _storage.write(key: _keyName, value: base64UrlEncode(bytes));
    return SecretKeyData(bytes);
  }
}

class InMemoryCacheCipher implements CacheCipher {
  static final _algorithm = AesGcm.with256bits();
  SecretKey? _key;

  @override
  Future<String> encrypt(String value) async {
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: await _loadKey(),
    );
    return 'aesgcm:v1:${base64UrlEncode(secretBox.nonce)}:${base64UrlEncode(secretBox.mac.bytes)}:${base64UrlEncode(secretBox.cipherText)}';
  }

  @override
  Future<String> decrypt(String value) async {
    if (!value.startsWith('aesgcm:v1:')) return value;
    final parts = value.substring('aesgcm:v1:'.length).split(':');
    if (parts.length != 3)
      throw const FormatException('Invalid encrypted cache');
    final clear = await _algorithm.decrypt(
      SecretBox(
        base64Url.decode(parts[2]),
        nonce: base64Url.decode(parts[0]),
        mac: Mac(base64Url.decode(parts[1])),
      ),
      secretKey: await _loadKey(),
    );
    return utf8.decode(clear);
  }

  @override
  Future<void> deleteKey() async {
    _key = null;
  }

  Future<SecretKey> _loadKey() async {
    return _key ??= SecretKeyData(
      Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      ),
    );
  }
}
