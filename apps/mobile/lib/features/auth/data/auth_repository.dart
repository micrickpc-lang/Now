import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/realtime_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/storage/token_store.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens, this._cache, this._demoMode);
  final ApiClient _api;
  final TokenStore _tokens;
  final LocalCache _cache;
  final bool _demoMode;

  Future<void> requestOtp(String phone) async {
    if (_demoMode) return;
    await _api.dio.post<void>(
      '/auth/otp/request',
      data: {'phone': phone},
      options: Options(extra: {'skipAuth': true}),
    );
  }

  Future<void> verify({
    required String phone,
    required String code,
    required DateTime birthDate,
    required String displayName,
  }) async {
    var installation = await _tokens.installationId();
    if (installation == null) {
      installation = const Uuid().v4();
      await _tokens.writeInstallationId(installation);
    }
    if (_demoMode) {
      if (code != '123456') {
        throw DioException(
          requestOptions: RequestOptions(path: '/auth/otp/verify'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/auth/otp/verify'),
            statusCode: 401,
            data: {'message': 'В демо-режиме используй код 123456'},
          ),
        );
      }
      await _tokens.write(
        accessToken: 'demo-access-token',
        refreshToken: 'demo-refresh-token',
      );
      return;
    }
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/auth/otp/verify',
      data: {
        'phone': phone,
        'code': code,
        'birthDate': birthDate.toIso8601String(),
        'displayName': displayName,
        'installationId': installation,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'deviceLabel': Platform.operatingSystemVersion,
      },
      options: Options(extra: {'skipAuth': true}),
    );
    await _tokens.write(
      accessToken: response.data!['accessToken'] as String,
      refreshToken: response.data!['refreshToken'] as String,
    );
  }

  Future<bool> hasSession() async => await _tokens.refresh() != null;

  Future<void> logout() async {
    final refresh = await _tokens.refresh();
    if (refresh != null && !_demoMode) {
      try {
        await _api.dio.post<void>(
          '/auth/logout',
          data: {'refreshToken': refresh},
        );
      } catch (_) {
        /* Local logout still proceeds. */
      }
    }
    await _tokens.clear();
    await _cache.clearSensitive();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localCacheProvider),
    ref.watch(appConfigProvider).demoMode,
  ),
);

class SessionController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(authRepositoryProvider).hasSession();

  Future<void> signedIn() async => state = const AsyncData(true);
  Future<void> logout() async {
    state = const AsyncLoading();
    await ref.read(realtimeCoordinatorProvider).stop();
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(false);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, bool>(
  SessionController.new,
);
