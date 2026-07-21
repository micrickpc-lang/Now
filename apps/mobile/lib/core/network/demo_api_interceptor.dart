import 'package:dio/dio.dart';

/// A deterministic, in-memory API used only by explicitly enabled dev builds.
/// It never runs in production because AppConfig rejects that combination.
class DemoApiInterceptor extends Interceptor {
  DemoApiInterceptor() {
    final now = DateTime.now().toUtc();
    _signals.addAll([
      {
        'id': 'demo-signal-1',
        'authorId': 'demo-friend-1',
        'category': 'walk',
        'text': 'Пойдём гулять через полчаса?',
        'emoji': '🌿',
        'startsAt': now.add(const Duration(minutes: 30)).toIso8601String(),
        'expiresAt': now.add(const Duration(hours: 2)).toIso8601String(),
        'state': 'ACTIVE',
        'districtLabel': 'рядом, без точного адреса',
        '_count': {'participants': 2},
        'author': {
          'profile': {'displayName': 'Аня', 'emoji': '🌸'},
        },
      },
      {
        'id': 'demo-signal-2',
        'authorId': 'demo-friend-2',
        'category': 'game',
        'text': 'Есть час на кооператив',
        'emoji': '🎮',
        'startsAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
        'state': 'ACTIVE',
        '_count': {'participants': 1},
        'author': {
          'profile': {'displayName': 'Миша', 'emoji': '🛸'},
        },
      },
    ]);
    _messages.addAll([
      {
        'id': 'demo-message-1',
        'authorId': 'demo-friend-1',
        'body': 'Встречаемся у входа через 20 минут',
        'createdAt': now.subtract(const Duration(minutes: 4)).toIso8601String(),
      },
      {
        'id': 'demo-message-2',
        'authorId': 'demo-user',
        'body': 'Я буду!',
        'createdAt': now.subtract(const Duration(minutes: 2)).toIso8601String(),
      },
    ]);
  }

  final List<Map<String, dynamic>> _signals = [];
  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _circles = [
    {
      'id': 'demo-circle-1',
      'name': 'Близкие',
      'emoji': '🫶',
      'members': [
        {'userId': 'demo-user'},
        {'userId': 'demo-friend-1'},
        {'userId': 'demo-friend-2'},
      ],
    },
  ];
  bool _locationShared = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    final method = options.method.toUpperCase();

    if (method == 'GET' && path == '/signals/feed') {
      return _resolve(handler, options, List<dynamic>.from(_signals));
    }
    if (method == 'POST' && path == '/signals') {
      final payload = Map<String, dynamic>.from(options.data as Map);
      final now = DateTime.now().toUtc();
      final duration = (payload['durationMinutes'] as num?)?.toInt() ?? 60;
      final row = <String, dynamic>{
        ...payload,
        'id': 'demo-signal-${_signals.length + 1}',
        'authorId': 'demo-user',
        'startsAt': payload['startsAt'] ?? now.toIso8601String(),
        'expiresAt': now.add(Duration(minutes: duration)).toIso8601String(),
        'state': 'ACTIVE',
        '_count': {'participants': 1},
        'author': {
          'profile': {'displayName': 'Ты', 'emoji': '✨'},
        },
      };
      _signals.insert(0, row);
      return _resolve(handler, options, row, 201);
    }
    if (method == 'POST' && RegExp(r'^/signals/[^/]+/join$').hasMatch(path)) {
      return _resolve(handler, options, {'success': true}, 201);
    }

    if (method == 'GET' && path == '/friends') {
      return _resolve(handler, options, _friends);
    }
    if (method == 'GET' && path == '/circles') {
      return _resolve(handler, options, List<dynamic>.from(_circles));
    }
    if (method == 'POST' && path == '/circles') {
      final body = Map<String, dynamic>.from(options.data as Map);
      final circle = <String, dynamic>{
        'id': 'demo-circle-${_circles.length + 1}',
        'name': body['name'] ?? 'Новый круг',
        'emoji': body['emoji'] ?? '✨',
        'members': [
          {'userId': 'demo-user'},
          for (final id in (body['memberIds'] as List<dynamic>? ?? const []))
            {'userId': id},
        ],
      };
      _circles.add(circle);
      return _resolve(handler, options, circle, 201);
    }
    if (method == 'POST' && path == '/friends/invites') {
      return _resolve(handler, options, {
        'token': 'demo-invite-token',
        'shortCode': 'DEMO2026',
        'deepLink': 'https://join.example.invalid/i/demo-invite-token',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .toIso8601String(),
      }, 201);
    }

    if (method == 'GET' && path == '/memories') {
      return _resolve(handler, options, [
        {
          'id': 'demo-memory-1',
          'title': 'Вечерняя прогулка',
          'category': 'walk',
          'occurredAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 3))
              .toIso8601String(),
          'theme': 'aurora',
        },
      ]);
    }

    final messages = RegExp(r'^/rooms/[^/]+/messages$');
    if (method == 'GET' && messages.hasMatch(path)) {
      return _resolve(handler, options, List<dynamic>.from(_messages));
    }
    if (method == 'POST' && messages.hasMatch(path)) {
      final body = Map<String, dynamic>.from(options.data as Map);
      _messages.add({
        'id': 'demo-message-${_messages.length + 1}',
        'authorId': 'demo-user',
        'body': body['body'] ?? '',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      return _resolve(handler, options, {'success': true}, 201);
    }
    if (RegExp(r'^/rooms/[^/]+/location-share$').hasMatch(path)) {
      if (method == 'POST') _locationShared = true;
      if (method == 'DELETE') _locationShared = false;
      return _resolve(handler, options, {'success': true});
    }
    if (method == 'GET' && RegExp(r'^/rooms/[^/]+$').hasMatch(path)) {
      return _resolve(handler, options, {
        'id': path.split('/').last,
        'title': 'Демо-комната',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String(),
        'locationShares': _locationShared
            ? [
                {
                  'ownerId': 'demo-user',
                  'expiresAt': DateTime.now()
                      .toUtc()
                      .add(const Duration(minutes: 30))
                      .toIso8601String(),
                },
              ]
            : <dynamic>[],
      });
    }

    if (method == 'GET' && path == '/users/me') {
      return _resolve(handler, options, {
        'id': 'demo-user',
        'limitedMode': false,
        'profile': {
          'displayName': 'Тестовый пользователь',
          'emoji': '✨',
          'showRecentActivity': false,
        },
      });
    }
    if (method == 'GET' && path == '/auth/sessions') {
      return _resolve(handler, options, [
        {
          'id': 'demo-session',
          'lastUsedAt': DateTime.now().toLocal().toIso8601String(),
          'device': {'platform': 'android', 'label': 'Этот Pixel · demo'},
        },
      ]);
    }
    if (method == 'GET' && path == '/users/me/blocks') {
      return _resolve(handler, options, <dynamic>[]);
    }
    if (method == 'GET' && path == '/maps/search') {
      final query = options.queryParameters['q']?.toString() ?? 'место';
      return _resolve(handler, options, [
        {
          'label': '$query · демонстрационная точка',
          'latitude': 43.7384,
          'longitude': 7.4246,
        },
      ]);
    }

    // Mutations not carrying useful response data are acknowledged locally.
    if (method == 'POST' || method == 'PATCH' || method == 'DELETE') {
      return _resolve(handler, options, {'success': true});
    }
    return _resolve(handler, options, <String, dynamic>{});
  }

  List<Map<String, dynamic>> get _friends => const [
    {
      'id': 'demo-friend-1',
      'profile': {'displayName': 'Аня', 'emoji': '🌸'},
    },
    {
      'id': 'demo-friend-2',
      'profile': {'displayName': 'Миша', 'emoji': '🛸'},
    },
    {
      'id': 'demo-friend-3',
      'profile': {'displayName': 'Лера', 'emoji': '☀️'},
    },
  ];

  void _resolve(
    RequestInterceptorHandler handler,
    RequestOptions request,
    dynamic data, [
    int statusCode = 200,
  ]) {
    handler.resolve(
      Response<dynamic>(
        requestOptions: request,
        data: data,
        statusCode: statusCode,
      ),
    );
  }
}
