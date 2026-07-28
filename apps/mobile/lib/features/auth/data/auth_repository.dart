import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/realtime_client.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/storage/token_store.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens, this._cache, this._demoMode);
  final ApiClient _api;
  final TokenStore _tokens;
  final LocalCache _cache;
  final bool _demoMode;

  static const profileCompletionTimeout = Duration(seconds: 15);

  Future<void> requestEmailCode(String email) async {
    if (_demoMode) return;
    await _api.dio.post<void>(
      '/auth/email/request-code',
      data: {'email': email},
      options: Options(extra: {'skipAuth': true}),
    );
  }

  Future<void> resendEmailCode(String email) async {
    if (_demoMode) return;
    await _api.dio.post<void>(
      '/auth/email/resend-code',
      data: {'email': email},
      options: Options(extra: {'skipAuth': true}),
    );
  }

  Future<bool> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    if (_demoMode) {
      if (code != '123456') {
        throw DioException(
          requestOptions: RequestOptions(path: '/auth/email/verify-code'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/auth/email/verify-code'),
            statusCode: 401,
            data: {'message': 'Use code 123456 in demo mode'},
          ),
        );
      }
      await _tokens.write(
        accessToken: 'demo-access-token',
        refreshToken: 'demo-refresh-token',
        profileComplete: false,
      );
      return false;
    }
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/auth/email/verify-code',
      data: {'email': email, 'code': code, ...await _devicePayload()},
      options: Options(extra: {'skipAuth': true}),
    );
    return _storeTokens(response.data!);
  }

  Future<bool> signInWithGoogle() async {
    if (_demoMode) {
      await _tokens.write(
        accessToken: 'demo-access-token',
        refreshToken: 'demo-refresh-token',
        profileComplete: false,
      );
      return false;
    }
    const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    final account = await GoogleSignIn(
      scopes: const ['email'],
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    ).signIn();
    if (account == null) throw const _AuthCancelled();
    final authentication = await account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null) {
      throw StateError('Google did not return an ID token');
    }
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/auth/google',
      data: {'idToken': idToken, ...await _devicePayload()},
      options: Options(extra: {'skipAuth': true}),
    );
    return _storeTokens(response.data!);
  }

  Future<void> completeProfile({
    required String displayName,
    required String username,
  }) async {
    if (!_demoMode) {
      await _api.dio
          .post<void>(
            '/auth/profile',
            data: {'displayName': displayName, 'username': username},
          )
          .timeout(profileCompletionTimeout);
    }
    await _tokens.writeProfileComplete(true);
  }

  Future<bool> hasSession() async => await _tokens.refresh() != null;
  Future<bool> profileComplete() => _tokens.profileComplete();

  Future<Map<String, String>> _devicePayload() async {
    var installation = await _tokens.installationId();
    if (installation == null) {
      installation = const Uuid().v4();
      await _tokens.writeInstallationId(installation);
    }
    return {
      'installationId': installation,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'deviceLabel': Platform.operatingSystemVersion,
      'appVersion': '0.1.0',
    };
  }

  Future<bool> _storeTokens(Map<String, dynamic> response) async {
    final user = response['user'] as Map<String, dynamic>?;
    final profileComplete = user?['profileComplete'] == true;
    await _tokens.write(
      accessToken: response['accessToken'] as String,
      refreshToken: response['refreshToken'] as String,
      profileComplete: profileComplete,
    );
    return profileComplete;
  }

  Future<void> logout() async {
    final refresh = await _tokens.refresh();
    if (refresh != null && !_demoMode) {
      try {
        await _api.dio.post<void>(
          '/auth/logout',
          data: {'refreshToken': refresh},
        );
      } catch (_) {
        // Local logout still proceeds when the network is unavailable.
      }
    }
    await _tokens.clear();
    await _cache.clearSensitive();
  }
}

class _AuthCancelled implements Exception {
  const _AuthCancelled();
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
