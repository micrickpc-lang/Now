import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'demo_api_interceptor.dart';

class ApiClient {
  ApiClient(this.dio, this._tokens);
  final Dio dio;
  final TokenStore _tokens;
  Completer<void>? _refreshing;
  final _sessionRefreshes = StreamController<void>.broadcast();

  Stream<void> get sessionRefreshes => _sessionRefreshes.stream;

  Future<void> refreshSession() async {
    if (_refreshing case final active?) return active.future;
    final completer = Completer<void>();
    _refreshing = completer;
    try {
      final refresh = await _tokens.refresh();
      if (refresh == null) throw StateError('No refresh token');
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
        options: Options(extra: {'skipAuth': true}),
      );
      await _tokens.write(
        accessToken: response.data!['accessToken'] as String,
        refreshToken: response.data!['refreshToken'] as String,
      );
      _sessionRefreshes.add(null);
      completer.complete();
    } catch (error, stack) {
      await _tokens.clear();
      completer.completeError(error, stack);
      rethrow;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> dispose() async {
    dio.close(force: true);
    await _sessionRefreshes.close();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStoreProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );
  late final ApiClient client;
  if (config.demoMode) dio.interceptors.add(DemoApiInterceptor());
  dio.interceptors.add(
    QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.extra['skipAuth'] != true) {
          final access = await tokens.access();
          if (access != null)
            options.headers['authorization'] = 'Bearer $access';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        if (error.response?.statusCode == 401 &&
            request.extra['skipAuth'] != true &&
            request.extra['retried'] != true) {
          try {
            await client.refreshSession();
            request.extra['retried'] = true;
            request.headers['authorization'] =
                'Bearer ${await tokens.access()}';
            return handler.resolve(await dio.fetch(request));
          } catch (_) {
            return handler.next(error);
          }
        }
        handler.next(error);
      },
    ),
  );
  client = ApiClient(dio, tokens);
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});
