import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/network/demo_api_interceptor.dart';

void main() {
  test('demo API serves and mutates local data without a network', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://demo.invalid'))
      ..interceptors.add(DemoApiInterceptor());

    final initial = await dio.get<List<dynamic>>('/signals/feed');
    expect(initial.data, hasLength(2));

    await dio.post<Map<String, dynamic>>(
      '/signals',
      data: {
        'category': 'talk',
        'text': 'Проверка демо',
        'durationMinutes': 30,
      },
    );
    final updated = await dio.get<List<dynamic>>('/signals/feed');
    expect(updated.data, hasLength(3));
    expect((updated.data!.first as Map)['text'], 'Проверка демо');
  });
}
