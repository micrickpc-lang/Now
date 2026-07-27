import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'api_client.dart';

enum RealtimeConnectionStatus {
  disconnected,
  connecting,
  connected,
  unauthenticated,
  offline,
  demo,
}

class RealtimeEvent {
  const RealtimeEvent({
    required this.id,
    required this.sequence,
    required this.occurredAt,
    required this.type,
    required this.payload,
  });

  factory RealtimeEvent.fromSocket(String type, dynamic raw) {
    final envelope = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final payloadValue = envelope['payload'] ?? raw;
    final payload = payloadValue is Map
        ? Map<String, dynamic>.from(payloadValue)
        : <String, dynamic>{'value': payloadValue};
    final occurredAt = DateTime.tryParse(
      envelope['occurredAt']?.toString() ?? '',
    );
    return RealtimeEvent(
      id:
          envelope['id']?.toString() ??
          '$type-${DateTime.now().microsecondsSinceEpoch}',
      sequence: (envelope['sequence'] as num?)?.toInt() ?? 0,
      occurredAt: occurredAt ?? DateTime.now().toUtc(),
      type: type,
      payload: payload,
    );
  }

  final String id;
  final int sequence;
  final DateTime occurredAt;
  final String type;
  final Map<String, dynamic> payload;
}

typedef RealtimeSocketFactory =
    io.Socket Function(String uri, Map<String, dynamic> options);

io.Socket _defaultSocketFactory(String uri, Map<String, dynamic> options) =>
    io.io(uri, options);

class RealtimeClient {
  RealtimeClient(
    this._config,
    this._tokens, {
    RealtimeSocketFactory? socketFactory,
    this._ackTimeout = const Duration(seconds: 5),
  }) : _socketFactory = socketFactory ?? _defaultSocketFactory;

  final AppConfig _config;
  final TokenStore _tokens;
  final RealtimeSocketFactory _socketFactory;
  final Duration _ackTimeout;
  io.Socket? _socket;
  io.Socket? _readySocket;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _statuses = StreamController<RealtimeConnectionStatus>.broadcast();
  final _authenticationErrors = StreamController<String>.broadcast();
  final Map<io.Socket, Set<Completer<bool>>> _pendingAcks = {};
  final Map<Completer<bool>, Timer> _ackTimers = {};
  Future<void>? _connectInFlight;
  int _connectionGeneration = 0;

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<RealtimeConnectionStatus> get statuses => _statuses.stream;
  Stream<String> get authenticationErrors => _authenticationErrors.stream;
  bool get isConnected => _socket != null && identical(_readySocket, _socket);

  Future<void> connect() {
    if (_config.demoMode) {
      if (!_statuses.isClosed) {
        _statuses.add(RealtimeConnectionStatus.demo);
      }
      return Future.value();
    }
    final inFlight = _connectInFlight;
    if (inFlight != null) return inFlight;
    final operation = _connect();
    _connectInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_connectInFlight, operation)) {
        _connectInFlight = null;
      }
    });
  }

  Future<void> _connect() async {
    if (_socket != null) return;
    final generation = _connectionGeneration;
    final token = await _tokens.access();
    if (generation != _connectionGeneration || _socket != null) return;
    if (token == null) {
      if (!_statuses.isClosed) {
        _statuses.add(RealtimeConnectionStatus.unauthenticated);
      }
      return;
    }
    if (!_statuses.isClosed) {
      _statuses.add(RealtimeConnectionStatus.connecting);
    }
    final socket = _socketFactory(
      '${_config.wsBaseUrl}/realtime',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(20)
          .setReconnectionDelay(800)
          .setReconnectionDelayMax(15000)
          .disableAutoConnect()
          .build(),
    );
    for (final name in _eventNames) {
      socket.on(name, (data) {
        if (!_events.isClosed) {
          _events.add(RealtimeEvent.fromSocket(name, data));
        }
      });
    }
    socket.onConnect((_) {
      if (identical(_socket, socket)) {
        _readySocket = null;
      }
    });
    socket.on('ready', (_) {
      if (identical(_socket, socket) &&
          !identical(_readySocket, socket) &&
          !_statuses.isClosed) {
        _readySocket = socket;
        _statuses.add(RealtimeConnectionStatus.connected);
      }
    });
    socket.on('auth.error', (data) {
      if (!_releaseSocket(socket)) return;
      final code = data is Map ? data['code']?.toString() : data?.toString();
      if (!_authenticationErrors.isClosed) {
        _authenticationErrors.add(code ?? 'unauthorized');
      }
      if (!_statuses.isClosed) {
        _statuses.add(RealtimeConnectionStatus.disconnected);
      }
    });
    socket.onDisconnect((_) {
      if (_releaseSocket(socket) && !_statuses.isClosed) {
        _statuses.add(RealtimeConnectionStatus.disconnected);
      }
    });
    socket.onConnectError((_) {
      if (_releaseSocket(socket) && !_statuses.isClosed) {
        _statuses.add(RealtimeConnectionStatus.disconnected);
      }
    });
    _socket = socket;
    socket.connect();
  }

  bool _releaseSocket(io.Socket socket) {
    if (!identical(_socket, socket)) return false;
    _socket = null;
    _readySocket = null;
    _connectionGeneration += 1;
    _failPendingAcks(socket);
    scheduleMicrotask(socket.dispose);
    return true;
  }

  Future<void> reconnectWithFreshToken() async {
    await disconnect();
    await connect();
  }

  Future<bool> subscribeRoom(String roomId) =>
      _emitWithAck('room.subscribe', {'roomId': roomId});

  Future<bool> unsubscribeRoom(String roomId) =>
      _emitWithAck('room.unsubscribe', {'roomId': roomId});

  Future<bool> subscribeConversation(String conversationId) => _emitWithAck(
    'conversation.subscribe',
    {'conversationId': conversationId},
  );

  Future<bool> unsubscribeConversation(String conversationId) => _emitWithAck(
    'conversation.unsubscribe',
    {'conversationId': conversationId},
  );

  Future<bool> _emitWithAck(String event, Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null || !identical(_readySocket, socket)) return false;

    final completer = Completer<bool>();
    _pendingAcks.putIfAbsent(socket, () => <Completer<bool>>{}).add(completer);
    _ackTimers[completer] = Timer(
      _ackTimeout,
      () => _completeAck(completer, false),
    );
    try {
      socket.emitWithAck(
        event,
        payload,
        ack: ([dynamic response]) {
          _completeAck(completer, _isSuccessfulAck(response));
        },
      );
      final acknowledged = await completer.future;
      return acknowledged &&
          identical(_socket, socket) &&
          identical(_readySocket, socket);
    } catch (_) {
      _completeAck(completer, false);
      return false;
    } finally {
      _ackTimers.remove(completer)?.cancel();
      final pending = _pendingAcks[socket];
      pending?.remove(completer);
      if (pending?.isEmpty ?? false) {
        _pendingAcks.remove(socket);
      }
    }
  }

  bool _isSuccessfulAck(dynamic response) =>
      response == true || (response is Map && response['ok'] == true);

  void _completeAck(Completer<bool> completer, bool acknowledged) {
    _ackTimers.remove(completer)?.cancel();
    if (!completer.isCompleted) completer.complete(acknowledged);
  }

  void _failPendingAcks(io.Socket socket) {
    final pending = _pendingAcks.remove(socket);
    if (pending == null) return;
    for (final completer in pending) {
      _completeAck(completer, false);
    }
  }

  Future<void> disconnect() async {
    _connectionGeneration += 1;
    final socket = _socket;
    _socket = null;
    _readySocket = null;
    if (socket != null) _failPendingAcks(socket);
    socket?.dispose();
    if (!_statuses.isClosed) {
      _statuses.add(RealtimeConnectionStatus.disconnected);
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _statuses.close();
    await _authenticationErrors.close();
  }
}

const _eventNames = [
  'signal.created',
  'signal.updated',
  'signal.cancelled',
  'signal.expired',
  'join.requested',
  'join.approved',
  'join.rejected',
  'room.member.joined',
  'room.member.left',
  'room.message.created',
  'room.poll.updated',
  'location.share.updated',
  'location.share.revoked',
  'conversation.created',
  'conversation.updated',
  'conversation.deleted',
  'conversation.member.added',
  'conversation.member.removed',
  'message.created',
  'message.updated',
  'message.deleted',
  'message.delivered',
  'message.read',
  'typing.started',
  'typing.stopped',
];

final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(
    ref.watch(appConfigProvider),
    ref.watch(tokenStoreProvider),
  );
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});

class RealtimeLease {
  RealtimeLease(this._release);
  final void Function() _release;
  bool _released = false;

  void close() {
    if (_released) return;
    _released = true;
    _release();
  }
}

class RealtimeCoordinator with WidgetsBindingObserver {
  RealtimeCoordinator(
    this._client,
    this._api,
    this._connectivity,
    this._demoMode, {
    this._reconnectBaseDelay = const Duration(milliseconds: 800),
  });

  final RealtimeClient _client;
  final ApiClient _api;
  final Connectivity _connectivity;
  final bool _demoMode;
  final Duration _reconnectBaseDelay;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _statuses = StreamController<RealtimeConnectionStatus>.broadcast();
  final Set<String> _seenIds = <String>{};
  final Map<String, int> _lastSequences = {};
  final Map<String, int> _roomReferences = {};
  final Map<String, int> _conversationReferences = {};
  StreamSubscription<RealtimeEvent>? _eventSubscription;
  StreamSubscription<RealtimeConnectionStatus>? _statusSubscription;
  StreamSubscription<String>? _authenticationErrorSubscription;
  StreamSubscription<void>? _refreshSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _reconnectTimer;
  Timer? _subscriptionRetryTimer;
  Future<void>? _authenticationRecovery;
  Future<void>? _freshReconnect;
  Future<void>? _subscriptionSync;
  final Set<String> _serverRoomSubscriptions = {};
  final Set<String> _serverConversationSubscriptions = {};
  int _lifecycleGeneration = 0;
  int _subscriptionGeneration = 0;
  int _reconnectAttempts = 0;
  int _subscriptionRetryAttempts = 0;
  bool _authenticationRecoveryAttempted = false;
  bool _subscriptionSyncRequested = false;
  bool _started = false;
  bool _foreground = true;
  bool _online = true;

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<RealtimeConnectionStatus> get statuses => _statuses.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _lifecycleGeneration += 1;
    WidgetsBinding.instance.addObserver(this);
    _eventSubscription = _client.events.listen(_handleEvent);
    _statusSubscription = _client.statuses.listen(_handleStatus);
    _authenticationErrorSubscription = _client.authenticationErrors.listen(
      _handleAuthenticationError,
    );
    _refreshSubscription = _api.sessionRefreshes.listen((_) {
      _requestFreshReconnect();
    });
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivity,
    );
    _handleConnectivity(await _connectivity.checkConnectivity());
    if (_demoMode) {
      _statuses.add(RealtimeConnectionStatus.demo);
    } else if (_foreground && _online) {
      await _client.connect();
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _lifecycleGeneration += 1;
    final authenticationRecovery = _authenticationRecovery;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _resetSubscriptionState();
    WidgetsBinding.instance.removeObserver(this);
    await _eventSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _authenticationErrorSubscription?.cancel();
    await _refreshSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    _eventSubscription = null;
    _statusSubscription = null;
    _authenticationErrorSubscription = null;
    _refreshSubscription = null;
    _connectivitySubscription = null;
    _roomReferences.clear();
    _conversationReferences.clear();
    _seenIds.clear();
    _lastSequences.clear();
    _reconnectAttempts = 0;
    _authenticationRecoveryAttempted = false;
    // Logout calls stop() before clearing tokens. Waiting for the single
    // in-flight refresh prevents that refresh from writing a new session after
    // the local logout has already completed.
    await authenticationRecovery;
    await _client.disconnect();
    await _subscriptionSync;
  }

  RealtimeLease subscribeRoom(String roomId) {
    _roomReferences.update(roomId, (value) => value + 1, ifAbsent: () => 1);
    _requestSubscriptionSync();
    return RealtimeLease(() {
      final remaining = (_roomReferences[roomId] ?? 1) - 1;
      if (remaining <= 0) {
        _roomReferences.remove(roomId);
        _requestSubscriptionSync();
      } else {
        _roomReferences[roomId] = remaining;
      }
    });
  }

  RealtimeLease subscribeConversation(String conversationId) {
    _conversationReferences.update(
      conversationId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _requestSubscriptionSync();
    return RealtimeLease(() {
      final remaining = (_conversationReferences[conversationId] ?? 1) - 1;
      if (remaining <= 0) {
        _conversationReferences.remove(conversationId);
        _requestSubscriptionSync();
      } else {
        _conversationReferences[conversationId] = remaining;
      }
    });
  }

  void emitDemo(RealtimeEvent event) {
    if (_demoMode) _handleEvent(event);
  }

  @visibleForTesting
  void beginConnectionGeneration() {
    // The API sequence is process-local. A reconnect can land on a restarted
    // process whose first valid event has a lower sequence than the old one.
    _lastSequences.clear();
  }

  void _handleEvent(RealtimeEvent event) {
    if (_seenIds.contains(event.id)) return;
    _seenIds.add(event.id);
    while (_seenIds.length > 512) {
      _seenIds.remove(_seenIds.first);
    }
    final scope =
        event.payload['conversationId']?.toString() ??
        event.payload['roomId']?.toString() ??
        event.type;
    final previous = _lastSequences[scope];
    if (event.sequence > 0 && previous != null && event.sequence <= previous) {
      return;
    }
    if (event.sequence > 0) _lastSequences[scope] = event.sequence;
    if (!_events.isClosed) _events.add(event);
  }

  void _handleStatus(RealtimeConnectionStatus status) {
    if (!_statuses.isClosed) _statuses.add(status);
    switch (status) {
      case RealtimeConnectionStatus.connected:
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _reconnectAttempts = 0;
        _authenticationRecoveryAttempted = false;
        beginConnectionGeneration();
        _resetSubscriptionState();
        _requestSubscriptionSync();
        break;
      case RealtimeConnectionStatus.disconnected:
        _resetSubscriptionState();
        _scheduleReconnect();
        break;
      case RealtimeConnectionStatus.unauthenticated:
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _resetSubscriptionState();
        break;
      case RealtimeConnectionStatus.connecting:
      case RealtimeConnectionStatus.offline:
      case RealtimeConnectionStatus.demo:
        break;
    }
  }

  void _handleAuthenticationError(String _) {
    if (!_canConnect || _authenticationRecovery != null) return;
    if (_authenticationRecoveryAttempted) {
      if (!_statuses.isClosed) {
        _statuses.add(RealtimeConnectionStatus.unauthenticated);
      }
      return;
    }
    _authenticationRecoveryAttempted = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final generation = _lifecycleGeneration;
    late final Future<void> recovery;
    recovery = () async {
      try {
        await _api.refreshSession();
      } catch (_) {
        if (_isCurrent(generation) && !_statuses.isClosed) {
          _statuses.add(RealtimeConnectionStatus.unauthenticated);
        }
      } finally {
        if (identical(_authenticationRecovery, recovery)) {
          _authenticationRecovery = null;
        }
      }
    }();
    _authenticationRecovery = recovery;
    unawaited(recovery);
  }

  bool get _canConnect => _started && _foreground && _online && !_demoMode;

  bool _isCurrent(int generation) =>
      generation == _lifecycleGeneration && _canConnect;

  void _scheduleReconnect() {
    if (!_canConnect ||
        _authenticationRecoveryAttempted ||
        _freshReconnect != null ||
        _reconnectTimer != null ||
        _reconnectAttempts >= 20) {
      return;
    }
    final exponent = _reconnectAttempts > 4 ? 4 : _reconnectAttempts;
    final delay = Duration(
      milliseconds: _reconnectBaseDelay.inMilliseconds * (1 << exponent),
    );
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_canConnect && !_authenticationRecoveryAttempted) {
        unawaited(_client.connect());
      }
    });
  }

  void _requestFreshReconnect() {
    if (!_canConnect || _freshReconnect != null) return;
    final generation = _lifecycleGeneration;
    late final Future<void> reconnect;
    reconnect = () async {
      try {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        await _client.disconnect();
        if (!_isCurrent(generation)) return;
        await _client.connect();
      } finally {
        if (identical(_freshReconnect, reconnect)) {
          _freshReconnect = null;
        }
      }
    }();
    _freshReconnect = reconnect;
    unawaited(reconnect);
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    _online = !results.contains(ConnectivityResult.none);
    if (!_online) {
      _statuses.add(RealtimeConnectionStatus.offline);
      unawaited(_client.disconnect());
    } else if (_started && _foreground && !_demoMode) {
      unawaited(_client.connect());
    }
  }

  void _resetSubscriptionState() {
    _subscriptionGeneration += 1;
    _subscriptionRetryTimer?.cancel();
    _subscriptionRetryTimer = null;
    _subscriptionRetryAttempts = 0;
    _subscriptionSyncRequested = false;
    _serverRoomSubscriptions.clear();
    _serverConversationSubscriptions.clear();
  }

  bool get _canSynchronizeSubscriptions =>
      _started && _client.isConnected && !_demoMode;

  bool _isCurrentSubscriptionGeneration(int generation) =>
      generation == _subscriptionGeneration && _canSynchronizeSubscriptions;

  bool get _subscriptionsOutOfSync =>
      _roomReferences.keys.any(
        (roomId) => !_serverRoomSubscriptions.contains(roomId),
      ) ||
      _serverRoomSubscriptions.any(
        (roomId) => !_roomReferences.containsKey(roomId),
      ) ||
      _conversationReferences.keys.any(
        (conversationId) =>
            !_serverConversationSubscriptions.contains(conversationId),
      ) ||
      _serverConversationSubscriptions.any(
        (conversationId) =>
            !_conversationReferences.containsKey(conversationId),
      );

  void _requestSubscriptionSync() {
    if (!_canSynchronizeSubscriptions) return;
    _subscriptionRetryTimer?.cancel();
    _subscriptionRetryTimer = null;
    if (_subscriptionSync != null) {
      _subscriptionSyncRequested = true;
      return;
    }

    final generation = _subscriptionGeneration;
    late final Future<void> sync;
    sync = _synchronizeSubscriptions(generation).whenComplete(() {
      if (identical(_subscriptionSync, sync)) {
        _subscriptionSync = null;
      }
      if (!_canSynchronizeSubscriptions) return;
      if (_subscriptionsOutOfSync) {
        if (_subscriptionSyncRequested) {
          _subscriptionSyncRequested = false;
          _requestSubscriptionSync();
        } else {
          _scheduleSubscriptionRetry();
        }
      } else {
        _subscriptionRetryAttempts = 0;
      }
    });
    _subscriptionSync = sync;
    unawaited(sync);
  }

  Future<void> _synchronizeSubscriptions(int generation) async {
    do {
      _subscriptionSyncRequested = false;
      if (!_isCurrentSubscriptionGeneration(generation)) return;

      for (final roomId
          in _serverRoomSubscriptions
              .where((roomId) => !_roomReferences.containsKey(roomId))
              .toList()) {
        final acknowledged = await _client.unsubscribeRoom(roomId);
        if (!_isCurrentSubscriptionGeneration(generation)) return;
        if (acknowledged) _serverRoomSubscriptions.remove(roomId);
      }
      for (final conversationId
          in _serverConversationSubscriptions
              .where(
                (conversationId) =>
                    !_conversationReferences.containsKey(conversationId),
              )
              .toList()) {
        final acknowledged = await _client.unsubscribeConversation(
          conversationId,
        );
        if (!_isCurrentSubscriptionGeneration(generation)) return;
        if (acknowledged) {
          _serverConversationSubscriptions.remove(conversationId);
        }
      }
      for (final roomId
          in _roomReferences.keys
              .where((roomId) => !_serverRoomSubscriptions.contains(roomId))
              .toList()) {
        final acknowledged = await _client.subscribeRoom(roomId);
        if (!_isCurrentSubscriptionGeneration(generation)) return;
        if (acknowledged) _serverRoomSubscriptions.add(roomId);
      }
      for (final conversationId
          in _conversationReferences.keys
              .where(
                (conversationId) =>
                    !_serverConversationSubscriptions.contains(conversationId),
              )
              .toList()) {
        final acknowledged = await _client.subscribeConversation(
          conversationId,
        );
        if (!_isCurrentSubscriptionGeneration(generation)) return;
        if (acknowledged) {
          _serverConversationSubscriptions.add(conversationId);
        }
      }
    } while (_subscriptionSyncRequested &&
        _isCurrentSubscriptionGeneration(generation));
  }

  void _scheduleSubscriptionRetry() {
    if (!_canSynchronizeSubscriptions ||
        !_subscriptionsOutOfSync ||
        _subscriptionRetryTimer != null) {
      return;
    }
    final exponent = _subscriptionRetryAttempts > 4
        ? 4
        : _subscriptionRetryAttempts;
    final delay = Duration(
      milliseconds: _reconnectBaseDelay.inMilliseconds * (1 << exponent),
    );
    _subscriptionRetryAttempts += 1;
    _subscriptionRetryTimer = Timer(delay, () {
      _subscriptionRetryTimer = null;
      _requestSubscriptionSync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _started && _online && !_demoMode) {
      unawaited(_client.connect());
    } else if (!_foreground) {
      unawaited(_client.disconnect());
    }
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    await _statuses.close();
  }
}

final realtimeCoordinatorProvider = Provider<RealtimeCoordinator>((ref) {
  final coordinator = RealtimeCoordinator(
    ref.watch(realtimeClientProvider),
    ref.watch(apiClientProvider),
    Connectivity(),
    ref.watch(appConfigProvider).demoMode,
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final realtimeStatusProvider = StreamProvider<RealtimeConnectionStatus>(
  (ref) => ref.watch(realtimeCoordinatorProvider).statuses,
);
