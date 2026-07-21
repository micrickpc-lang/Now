import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import '../storage/token_store.dart';

class RealtimeClient {
  RealtimeClient(this._config, this._tokens);
  final AppConfig _config;
  final TokenStore _tokens;
  io.Socket? _socket;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> connect() async {
    await disconnect();
    if (_config.demoMode) return;
    final token = await _tokens.access();
    if (token == null) return;
    final socket = io.io(
      '${_config.wsBaseUrl}/realtime',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(800)
          .setReconnectionDelayMax(15000)
          .disableAutoConnect()
          .build(),
    );
    const names = [
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
    ];
    for (final name in names) {
      socket.on(name, (data) => _events.add({'type': name, 'data': data}));
    }
    socket.connect();
    _socket = socket;
  }

  void subscribeRoom(String roomId) =>
      _socket?.emit('room.subscribe', {'roomId': roomId});

  Future<void> disconnect() async {
    _socket?.dispose();
    _socket = null;
  }
}

final realtimeClientProvider = Provider<RealtimeClient>(
  (ref) => RealtimeClient(
    ref.watch(appConfigProvider),
    ref.watch(tokenStoreProvider),
  ),
);
