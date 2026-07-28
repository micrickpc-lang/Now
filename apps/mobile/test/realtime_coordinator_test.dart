import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seychas/core/config/app_config.dart';
import 'package:seychas/core/network/api_client.dart';
import 'package:seychas/core/network/realtime_client.dart';
import 'package:seychas/core/storage/token_store.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class _MockTokenStore extends Mock implements TokenStore {}

class _MockSocket extends Mock implements io.Socket {}

class _MockApiClient extends Mock implements ApiClient {}

class _MockConnectivity extends Mock implements Connectivity {}

class _SocketHarness {
  _SocketHarness() {
    when(() => socket.connected).thenAnswer((_) => connected);
    when(() => socket.connect()).thenReturn(socket);
    when(() => socket.on(any(), any())).thenAnswer((invocation) {
      final event = invocation.positionalArguments[0] as String;
      final handler = invocation.positionalArguments[1] as Function;
      handlers[event] = handler;
      return () => handlers.remove(event);
    });
    when(
      () => socket.emitWithAck(any(), any(), ack: any(named: 'ack')),
    ).thenAnswer((invocation) {
      final event = invocation.positionalArguments[0] as String;
      final data = invocation.positionalArguments[1];
      final ack = invocation.namedArguments[#ack] as Function?;
      emissions.add((event: event, data: data));
      final responses = ackResponses[event];
      if (ack != null && responses != null && responses.isNotEmpty) {
        final response = responses.removeAt(0);
        scheduleMicrotask(
          () => Function.apply(ack, [
            {'ok': response},
          ]),
        );
      }
    });
  }

  final socket = _MockSocket();
  final handlers = <String, Function>{};
  final emissions = <({String event, dynamic data})>[];
  final ackResponses = <String, List<bool>>{};
  bool connected = false;
  late Map<String, dynamic> options;

  void queueAcks(String event, List<bool> responses) {
    ackResponses[event] = [...responses];
  }

  void fire(String event, [dynamic data]) {
    if (event == 'connect') connected = true;
    if (event == 'disconnect' ||
        event == 'connect_error' ||
        event == 'auth.error') {
      connected = false;
    }
    final handler = handlers[event];
    if (handler == null) throw StateError('No handler for $event');
    Function.apply(handler, [data]);
  }
}

const _productionConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://api.invalid/api/v1',
  wsBaseUrl: 'http://api.invalid',
  firstPartyDomains: {},
  demoMode: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'coordinator deduplicates ids and drops stale sequence numbers',
    () async {
      final container = ProviderContainer(
        overrides: [
          baseAppConfigProvider.overrideWithValue(
            const AppConfig(
              environment: AppEnvironment.development,
              apiBaseUrl: 'http://demo.invalid/api/v1',
              wsBaseUrl: 'http://demo.invalid',
              firstPartyDomains: {},
              demoMode: true,
            ),
          ),
          initialDemoModeProvider.overrideWithValue(true),
        ],
      );
      final coordinator = container.read(realtimeCoordinatorProvider);
      final received = <RealtimeEvent>[];
      final subscription = coordinator.events.listen(received.add);
      final first = RealtimeEvent(
        id: 'event-1',
        sequence: 2,
        occurredAt: DateTime.now(),
        type: 'message.created',
        payload: const {'conversationId': 'chat'},
      );
      coordinator.emitDemo(first);
      coordinator.emitDemo(first);
      coordinator.emitDemo(
        RealtimeEvent(
          id: 'event-stale',
          sequence: 1,
          occurredAt: DateTime.now(),
          type: 'message.updated',
          payload: const {'conversationId': 'chat'},
        ),
      );
      coordinator.emitDemo(
        RealtimeEvent(
          id: 'event-3',
          sequence: 3,
          occurredAt: DateTime.now(),
          type: 'message.updated',
          payload: const {'conversationId': 'chat'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received.map((event) => event.id), ['event-1', 'event-3']);

      coordinator.beginConnectionGeneration();
      coordinator.emitDemo(
        RealtimeEvent(
          id: 'event-after-server-restart',
          sequence: 1,
          occurredAt: DateTime.now(),
          type: 'message.created',
          payload: const {'conversationId': 'chat'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received.map((event) => event.id), [
        'event-1',
        'event-3',
        'event-after-server-restart',
      ]);
      await subscription.cancel();
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'client releases a server-disconnected socket and can connect again',
    () async {
      final tokens = _MockTokenStore();
      var accessToken = 'expired-access';
      when(() => tokens.access()).thenAnswer((_) async => accessToken);
      final sockets = <_SocketHarness>[];
      final client = RealtimeClient(
        _productionConfig,
        tokens,
        socketFactory: (uri, options) {
          final harness = _SocketHarness()..options = options;
          sockets.add(harness);
          return harness.socket;
        },
      );
      addTearDown(client.dispose);

      await client.connect();
      expect(sockets, hasLength(1));
      expect((sockets.first.options['auth'] as Map)['token'], 'expired-access');

      final authenticationError = client.authenticationErrors.first;
      sockets.first.fire('auth.error', {'code': 'access_expired'});
      expect(await authenticationError, 'access_expired');
      accessToken = 'fresh-access';
      await client.connect();

      expect(sockets, hasLength(2));
      expect((sockets[1].options['auth'] as Map)['token'], 'fresh-access');

      sockets[1].fire('disconnect', 'io server disconnect');
      await Future<void>.delayed(Duration.zero);
      await client.connect();
      expect(sockets, hasLength(3));
    },
  );

  test('client reports connected only after authenticated ready', () async {
    final tokens = _MockTokenStore();
    when(() => tokens.access()).thenAnswer((_) async => 'access-token');
    late final _SocketHarness socket;
    final client = RealtimeClient(
      _productionConfig,
      tokens,
      socketFactory: (uri, options) {
        socket = _SocketHarness()..options = options;
        return socket.socket;
      },
    );
    final statuses = <RealtimeConnectionStatus>[];
    final subscription = client.statuses.listen(statuses.add);
    addTearDown(() async {
      await subscription.cancel();
      await client.dispose();
    });

    await client.connect();
    await Future<void>.delayed(Duration.zero);
    expect(statuses, [RealtimeConnectionStatus.connecting]);
    expect(client.isConnected, isFalse);

    socket.fire('connect');
    await Future<void>.delayed(Duration.zero);
    expect(statuses, [RealtimeConnectionStatus.connecting]);
    expect(client.isConnected, isFalse);

    socket.fire('ready', {'heartbeatSeconds': 25});
    await Future<void>.delayed(Duration.zero);
    expect(statuses, [
      RealtimeConnectionStatus.connecting,
      RealtimeConnectionStatus.connected,
    ]);
    expect(client.isConnected, isTrue);

    socket.fire('ready', {'heartbeatSeconds': 25});
    await Future<void>.delayed(Duration.zero);
    expect(
      statuses.where((status) => status == RealtimeConnectionStatus.connected),
      hasLength(1),
    );
  });

  test(
    'coordinator retries rejected acks and recreates subscriptions after ready',
    () async {
      final tokens = _MockTokenStore();
      when(() => tokens.access()).thenAnswer((_) async => 'access-token');
      final sockets = <_SocketHarness>[];
      final client = RealtimeClient(
        _productionConfig,
        tokens,
        ackTimeout: const Duration(milliseconds: 50),
        socketFactory: (uri, options) {
          final harness = _SocketHarness()..options = options;
          sockets.add(harness);
          return harness.socket;
        },
      );
      final api = _MockApiClient();
      final refreshes = StreamController<void>.broadcast();
      when(() => api.sessionRefreshes).thenAnswer((_) => refreshes.stream);
      final connectivity = _MockConnectivity();
      final connectivityChanges =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(
        () => connectivity.onConnectivityChanged,
      ).thenAnswer((_) => connectivityChanges.stream);
      when(
        () => connectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.wifi]);
      final coordinator = RealtimeCoordinator(
        client,
        api,
        connectivity,
        false,
        reconnectBaseDelay: const Duration(milliseconds: 5),
      );
      final lease = coordinator.subscribeConversation('conversation-1');
      addTearDown(() async {
        lease.close();
        await coordinator.dispose();
        await client.dispose();
        await refreshes.close();
        await connectivityChanges.close();
      });

      await coordinator.start();
      expect(sockets, hasLength(1));
      sockets.first.queueAcks('conversation.subscribe', [false, true]);
      sockets.first.fire('connect');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sockets.first.emissions, isEmpty);

      sockets.first.fire('ready', {'heartbeatSeconds': 25});
      await _eventually(
        () =>
            sockets.first.emissions
                .where((emission) => emission.event == 'conversation.subscribe')
                .length ==
            2,
      );
      expect(sockets.first.emissions.last.data, {
        'conversationId': 'conversation-1',
      });

      sockets.first.fire('disconnect', 'transport close');
      await _eventually(() => sockets.length == 2);
      sockets[1].queueAcks('conversation.subscribe', [true]);
      sockets[1].fire('connect');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sockets[1].emissions, isEmpty);

      sockets[1].fire('ready', {'heartbeatSeconds': 25});
      await _eventually(
        () => sockets[1].emissions.any(
          (emission) => emission.event == 'conversation.subscribe',
        ),
      );

      sockets[1].queueAcks('conversation.unsubscribe', [false, true]);
      lease.close();
      await _eventually(
        () =>
            sockets[1].emissions
                .where(
                  (emission) => emission.event == 'conversation.unsubscribe',
                )
                .length ==
            2,
      );
    },
  );

  test(
    'auth error refreshes once and reconnects with the fresh token',
    () async {
      final tokens = _MockTokenStore();
      var accessToken = 'expired-access';
      when(() => tokens.access()).thenAnswer((_) async => accessToken);
      final sockets = <_SocketHarness>[];
      final client = RealtimeClient(
        _productionConfig,
        tokens,
        socketFactory: (uri, options) {
          final harness = _SocketHarness()..options = options;
          sockets.add(harness);
          return harness.socket;
        },
      );
      final api = _MockApiClient();
      final refreshes = StreamController<void>.broadcast();
      var refreshCalls = 0;
      when(() => api.sessionRefreshes).thenAnswer((_) => refreshes.stream);
      when(() => api.refreshSession()).thenAnswer((_) async {
        refreshCalls += 1;
        accessToken = 'fresh-access';
        refreshes.add(null);
      });
      final connectivity = _MockConnectivity();
      final connectivityChanges =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(
        () => connectivity.onConnectivityChanged,
      ).thenAnswer((_) => connectivityChanges.stream);
      when(
        () => connectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.wifi]);
      final coordinator = RealtimeCoordinator(
        client,
        api,
        connectivity,
        false,
        reconnectBaseDelay: const Duration(milliseconds: 5),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
        await refreshes.close();
        await connectivityChanges.close();
      });

      await coordinator.start();
      expect(sockets, hasLength(1));
      sockets.first.fire('auth.error', {'code': 'access_expired'});
      await _eventually(() => sockets.length == 2);

      expect(refreshCalls, 1);
      expect((sockets[1].options['auth'] as Map)['token'], 'fresh-access');

      // A fresh token rejected before a successful connection must not cause an
      // unbounded refresh loop.
      sockets[1].fire('auth.error', {'code': 'unauthorized'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(refreshCalls, 1);
      expect(sockets, hasLength(2));
    },
  );

  test('logout while auth refresh is pending cannot reconnect', () async {
    final tokens = _MockTokenStore();
    var accessToken = 'expired-access';
    when(() => tokens.access()).thenAnswer((_) async => accessToken);
    final sockets = <_SocketHarness>[];
    final client = RealtimeClient(
      _productionConfig,
      tokens,
      socketFactory: (uri, options) {
        final harness = _SocketHarness()..options = options;
        sockets.add(harness);
        return harness.socket;
      },
    );
    final api = _MockApiClient();
    final refreshes = StreamController<void>.broadcast();
    final refreshCompleter = Completer<void>();
    var refreshCalls = 0;
    when(() => api.sessionRefreshes).thenAnswer((_) => refreshes.stream);
    when(() => api.refreshSession()).thenAnswer((_) async {
      refreshCalls += 1;
      await refreshCompleter.future;
      accessToken = 'fresh-after-logout';
      refreshes.add(null);
    });
    final connectivity = _MockConnectivity();
    final connectivityChanges =
        StreamController<List<ConnectivityResult>>.broadcast();
    when(
      () => connectivity.onConnectivityChanged,
    ).thenAnswer((_) => connectivityChanges.stream);
    when(
      () => connectivity.checkConnectivity(),
    ).thenAnswer((_) async => [ConnectivityResult.wifi]);
    final coordinator = RealtimeCoordinator(
      client,
      api,
      connectivity,
      false,
      reconnectBaseDelay: const Duration(milliseconds: 5),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
      await refreshes.close();
      await connectivityChanges.close();
    });

    await coordinator.start();
    sockets.first.fire('auth.error', {'code': 'access_expired'});
    await _eventually(() => refreshCalls == 1);
    final stopping = coordinator.stop();
    refreshCompleter.complete();
    await stopping;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(sockets, hasLength(1));
  });
}

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not met before timeout');
}
