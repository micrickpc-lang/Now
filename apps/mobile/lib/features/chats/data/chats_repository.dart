import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/realtime_client.dart';
import '../../../core/storage/local_cache.dart';
import '../domain/chat_models.dart';

class ChatsRepository {
  ChatsRepository(this._api, this._cache, this._realtime, this._demoMode);

  final ApiClient _api;
  final LocalCache _cache;
  final RealtimeCoordinator _realtime;
  final bool _demoMode;

  Future<String> currentUserId() async {
    if (_demoMode) return 'demo-user';
    final cached = await _cache.setting('account.current_user_id');
    if (cached != null) return cached;
    final response = await _api.dio.get<Map<String, dynamic>>('/users/me');
    final id = response.data!['id'] as String;
    await _cache.writeSetting('account.current_user_id', id);
    return id;
  }

  Future<ConversationPage> conversations() async {
    if (_demoMode) {
      await _ensureDemoSeed();
      return ConversationPage(items: await _cachedConversations());
    }
    try {
      final conversations = <String, ConversationSummary>{};
      final seenCursors = <String>{};
      String? cursor;
      do {
        final response = await _api.dio.get<dynamic>(
          '/conversations',
          queryParameters: {'limit': 100, 'cursor': ?cursor},
        );
        final page = await _conversationPage(response.data);
        for (final conversation in page.items) {
          conversations[conversation.id] = conversation;
        }
        final nextCursor = page.nextCursor;
        if (nextCursor == null) {
          cursor = null;
        } else if (!seenCursors.add(nextCursor)) {
          throw StateError('Conversation pagination cursor repeated');
        } else {
          cursor = nextCursor;
        }
      } while (cursor != null);

      final items = conversations.values.toList();
      // Retention is intentionally deferred until every cursor page has been
      // fetched. A failed or malformed later page must never delete cached
      // messages, drafts, or pending outbox entries for an unseen chat.
      await _cache.retainConversations(items.map((item) => item.id).toSet());
      for (final conversation in items) {
        await _saveConversation(conversation);
      }
      return ConversationPage(items: items);
    } catch (_) {
      final cached = await _cachedConversations();
      if (cached.isEmpty) rethrow;
      return ConversationPage(items: cached);
    }
  }

  Future<ConversationSummary> conversation(String id) async {
    if (_demoMode) {
      await _ensureDemoSeed();
      final cached = await _cache.cachedConversation(id);
      if (cached == null) throw StateError('Чат не найден');
      return _conversationForViewer(
        ConversationSummary.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        ),
        await currentUserId(),
      );
    }
    try {
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/conversations/$id',
      );
      final conversation = _conversationForViewer(
        ConversationSummary.fromJson(response.data!),
        await currentUserId(),
      );
      await _saveConversation(conversation);
      return conversation;
    } catch (_) {
      final cached = await _cache.cachedConversation(id);
      if (cached == null) rethrow;
      return _conversationForViewer(
        ConversationSummary.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        ),
        await currentUserId(),
      );
    }
  }

  Future<ConversationSummary> createDirect({
    required String friendId,
    required String displayName,
    String? emoji,
  }) async {
    if (!_demoMode) {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/conversations/direct',
        data: {'friendId': friendId},
      );
      final conversation = _conversationForViewer(
        ConversationSummary.fromJson(response.data!),
        await currentUserId(),
      );
      await _saveConversation(conversation);
      return conversation;
    }
    await _ensureDemoSeed();
    final conversations = await _cachedConversations();
    for (final conversation in conversations) {
      if (conversation.type == ConversationType.direct &&
          conversation.members.any((member) => member.userId == friendId)) {
        return conversation;
      }
    }
    final now = DateTime.now();
    final conversation = ConversationSummary(
      id: 'demo-direct-$friendId',
      type: ConversationType.direct,
      createdAt: now,
      updatedAt: now,
      members: [
        const ConversationMember(
          userId: 'demo-user',
          role: ConversationRole.member,
          displayName: 'Ты',
          emoji: '✨',
        ),
        ConversationMember(
          userId: friendId,
          role: ConversationRole.member,
          displayName: displayName,
          emoji: emoji,
        ),
      ],
    );
    await _saveConversation(conversation);
    return conversation;
  }

  Future<ConversationSummary> createGroup({
    required String title,
    required List<ConversationMember> members,
  }) async {
    if (!_demoMode) {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/conversations/group',
        data: {
          'title': title,
          'memberIds': members.map((member) => member.userId).toList(),
        },
      );
      final conversation = _conversationForViewer(
        ConversationSummary.fromJson(response.data!),
        await currentUserId(),
      );
      await _saveConversation(conversation);
      return conversation;
    }
    await _ensureDemoSeed();
    final now = DateTime.now();
    final id = 'demo-group-${const Uuid().v4()}';
    final conversation = ConversationSummary(
      id: id,
      type: ConversationType.group,
      title: title,
      ownerId: 'demo-user',
      createdAt: now,
      updatedAt: now,
      role: ConversationRole.owner,
      members: [
        const ConversationMember(
          userId: 'demo-user',
          role: ConversationRole.owner,
          displayName: 'Ты',
          emoji: '✨',
        ),
        ...members,
      ],
    );
    await _saveConversation(conversation);
    return conversation;
  }

  Future<MessagePage> messages(
    String conversationId, {
    String? cursor,
    int limit = 30,
  }) async {
    if (_demoMode) {
      await _ensureDemoSeed();
      return _cachedMessagePage(conversationId, cursor: cursor, limit: limit);
    }
    try {
      final response = await _api.dio.get<dynamic>(
        '/conversations/$conversationId/messages',
        queryParameters: {
          'limit': limit,
          ...cursor == null ? const {} : {'cursor': cursor},
        },
      );
      final page = await _messagePage(response.data);
      for (final message in page.items) {
        await _saveMessage(message);
      }
      return page;
    } catch (_) {
      final cached = await _cachedMessagePage(
        conversationId,
        cursor: cursor,
        limit: limit,
      );
      if (cached.items.isEmpty && cursor == null) rethrow;
      return cached;
    }
  }

  Future<ChatMessage> createPendingText(String conversationId, String text) =>
      _createPending(
        conversationId: conversationId,
        type: ChatMessageType.text,
        text: text,
      );

  Future<ChatMessage> createPendingSignal(
    String conversationId,
    String signalId,
  ) => _createPending(
    conversationId: conversationId,
    type: ChatMessageType.signal,
    metadata: {'signalId': signalId},
  );

  Future<ChatMessage> _createPending({
    required String conversationId,
    required ChatMessageType type,
    String? text,
    Map<String, dynamic> metadata = const {},
  }) async {
    final clientMessageId = const Uuid().v4();
    final message = ChatMessage(
      id: 'local-$clientMessageId',
      conversationId: conversationId,
      senderId: await currentUserId(),
      clientMessageId: clientMessageId,
      type: type,
      text: text,
      metadata: metadata,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.pending,
    );
    final request = _requestFor(message);
    await _saveMessage(message);
    await _cache.enqueue(
      id: clientMessageId,
      method: 'POST',
      path: '/conversations/$conversationId/messages',
      payload: jsonEncode(request),
    );
    await _updateConversationWithMessage(message);
    return message;
  }

  Future<ChatMessage> deliverPending(ChatMessage pending) async {
    final clientMessageId = pending.clientMessageId!;
    try {
      late final ChatMessage delivered;
      if (_demoMode) {
        delivered = pending.copyWith(
          id: 'demo-$clientMessageId',
          deliveryStatus: MessageDeliveryStatus.delivered,
        );
      } else {
        final response = await _api.dio.post<Map<String, dynamic>>(
          '/conversations/${pending.conversationId}/messages',
          data: _requestFor(pending),
        );
        delivered = ChatMessage.fromJson(
          response.data!,
        ).normalizeDeliveryForViewer(await currentUserId());
      }
      if (delivered.id != pending.id) {
        await _cache.removeCachedMessage(pending.id);
      }
      await _saveMessage(delivered);
      await _cache.removeOutbox(clientMessageId);
      await _updateConversationWithMessage(delivered);
      if (_demoMode) _emitDemoMessage(delivered);
      return delivered;
    } on DioException catch (error) {
      if (!_isRetryable(error)) {
        await _cache.removeOutbox(clientMessageId);
      }
      final failed = pending.copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
      await _saveMessage(failed);
      await _updateConversationWithMessage(failed);
      return failed;
    } catch (_) {
      final failed = pending.copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
      await _saveMessage(failed);
      await _updateConversationWithMessage(failed);
      return failed;
    }
  }

  Future<List<ChatMessage>> retryOutbox(String conversationId) async {
    final path = '/conversations/$conversationId/messages';
    final entries = await _cache.outbox(path: path);
    final results = <ChatMessage>[];
    for (final entry in entries) {
      final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
      final localRows = await _cache.cachedMessages(conversationId, limit: 200);
      final pending = localRows
          .map(
            (row) =>
                ChatMessage.fromJson(jsonDecode(row) as Map<String, dynamic>),
          )
          .where((message) => message.clientMessageId == entry.id)
          .firstOrNull;
      if (pending == null) {
        await _cache.removeOutbox(entry.id);
        continue;
      }
      if (_demoMode) {
        results.add(await deliverPending(pending));
        continue;
      }
      try {
        final response = await _api.dio.post<Map<String, dynamic>>(
          entry.path,
          data: payload,
        );
        final delivered = ChatMessage.fromJson(
          response.data!,
        ).normalizeDeliveryForViewer(await currentUserId());
        if (delivered.id != pending.id) {
          await _cache.removeCachedMessage(pending.id);
        }
        await _saveMessage(delivered);
        await _cache.removeOutbox(entry.id);
        await _updateConversationWithMessage(delivered);
        results.add(delivered);
      } on DioException catch (error) {
        if (!_isRetryable(error)) {
          await _cache.removeOutbox(entry.id);
        }
        final failed = pending.copyWith(
          deliveryStatus: MessageDeliveryStatus.failed,
        );
        await _saveMessage(failed);
        results.add(failed);
      }
    }
    return results;
  }

  Future<List<ChatMessage>> retryAllOutbox() async {
    final conversationIds = <String>{};
    final entries = await _cache.outbox();
    final messagePattern = RegExp(r'^/conversations/([^/]+)/messages$');
    final readPattern = RegExp(r'^/messages/[^/]+/read$');
    for (final entry in entries) {
      final match = messagePattern.firstMatch(entry.path);
      if (entry.method == 'POST' && match != null) {
        conversationIds.add(match.group(1)!);
      }
    }
    final results = <ChatMessage>[];
    for (final conversationId in conversationIds) {
      results.addAll(await retryOutbox(conversationId));
    }
    for (final entry in entries) {
      if (entry.method != 'POST' || !readPattern.hasMatch(entry.path)) {
        continue;
      }
      try {
        await _api.dio.post<void>(entry.path);
        await _cache.removeOutbox(entry.id);
      } on DioException catch (error) {
        if (!_isRetryable(error)) {
          await _cache.removeOutbox(entry.id);
        }
      }
    }
    return results;
  }

  Future<void> markRead(ChatMessage message) async {
    final userId = await currentUserId();
    if (message.senderId == null || message.senderId == userId) return;
    final now = DateTime.now();
    final updated = message.copyWith(
      readReceipts: [
        ...message.readReceipts.where((receipt) => receipt.userId != userId),
        MessageReadReceipt(userId: userId, readAt: now),
      ],
      deliveryStatus: MessageDeliveryStatus.read,
    );
    await _saveMessage(updated);
    final cached = await _cache.cachedConversation(message.conversationId);
    if (cached != null) {
      final conversation = ConversationSummary.fromJson(
        jsonDecode(cached) as Map<String, dynamic>,
      );
      await _saveConversation(conversation.copyWith(unreadCount: 0));
    }
    if (_demoMode) return;
    final outboxId = 'read:${message.id}';
    final path = '/messages/${message.id}/read';
    await _cache.enqueue(
      id: outboxId,
      method: 'POST',
      path: path,
      payload: jsonEncode({
        'conversationId': message.conversationId,
        'messageId': message.id,
      }),
    );
    try {
      await _api.dio.post<void>(path);
      await _cache.removeOutbox(outboxId);
    } on DioException catch (error) {
      if (!_isRetryable(error)) {
        await _cache.removeOutbox(outboxId);
      }
    }
  }

  Future<String> draft(String conversationId) async =>
      await _cache.draft(conversationId) ?? '';

  Future<void> saveDraft(String conversationId, String body) =>
      _cache.saveDraft(conversationId, body);

  Future<ChatMessage?> applyRealtime(RealtimeEvent event) async {
    if (!event.type.startsWith('message.')) return null;
    final raw = event.payload['message'];
    if (raw is! Map) return null;
    final message = ChatMessage.fromJson(
      Map<String, dynamic>.from(raw),
    ).normalizeDeliveryForViewer(await currentUserId());
    await _saveMessage(message);
    await _updateConversationWithMessage(message);
    return message;
  }

  Future<void> persistRealtimeState(ChatMessage message) =>
      _saveMessage(message);

  Future<void> _ensureDemoSeed() async {
    final existing = await _cache.setting('demo.messenger.seeded.v1');
    final cached = await _cache.cachedConversation('demo-direct-anya');
    if (existing == 'true' && cached != null) return;

    final now = DateTime.now();
    final directMessages = [
      ChatMessage(
        id: 'demo-direct-message-1',
        conversationId: 'demo-direct-anya',
        senderId: 'demo-friend-1',
        type: ChatMessageType.text,
        text: 'Ты сегодня свободен после семи?',
        createdAt: now.subtract(const Duration(minutes: 18)),
        deliveryStatus: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'demo-direct-message-2',
        conversationId: 'demo-direct-anya',
        senderId: 'demo-user',
        type: ChatMessageType.text,
        text: 'Да, давай пройдёмся у набережной.',
        createdAt: now.subtract(const Duration(minutes: 15)),
        readReceipts: [
          MessageReadReceipt(
            userId: 'demo-friend-1',
            readAt: now.subtract(const Duration(minutes: 14)),
          ),
        ],
        deliveryStatus: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'demo-direct-message-3',
        conversationId: 'demo-direct-anya',
        senderId: 'demo-friend-1',
        type: ChatMessageType.text,
        text: 'Отлично. Создадим сигнал ближе к вечеру.',
        createdAt: now.subtract(const Duration(minutes: 12)),
        deliveryStatus: MessageDeliveryStatus.delivered,
      ),
      ChatMessage(
        id: 'demo-direct-message-signal',
        conversationId: 'demo-direct-anya',
        senderId: 'demo-friend-1',
        type: ChatMessageType.signal,
        metadata: const {'signalId': 'demo-signal-1'},
        createdAt: now.subtract(const Duration(minutes: 10)),
        deliveryStatus: MessageDeliveryStatus.delivered,
      ),
    ];
    final groupMessages = [
      ChatMessage(
        id: 'demo-group-message-1',
        conversationId: 'demo-group-close',
        senderId: 'demo-friend-2',
        type: ChatMessageType.text,
        text: 'Кто за настолки в субботу?',
        createdAt: now.subtract(const Duration(hours: 2)),
        deliveryStatus: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'demo-group-message-2',
        conversationId: 'demo-group-close',
        senderId: 'demo-friend-1',
        type: ChatMessageType.text,
        text: 'Я за. Напомните утром 🙂',
        createdAt: now.subtract(const Duration(hours: 1, minutes: 48)),
        deliveryStatus: MessageDeliveryStatus.delivered,
      ),
    ];
    for (final message in [...directMessages, ...groupMessages]) {
      await _saveMessage(message);
    }
    final me = const ConversationMember(
      userId: 'demo-user',
      role: ConversationRole.member,
      displayName: 'Ты',
      emoji: '✨',
    );
    await _saveConversation(
      ConversationSummary(
        id: 'demo-direct-anya',
        type: ConversationType.direct,
        createdAt: now.subtract(const Duration(days: 45)),
        updatedAt: directMessages.last.createdAt,
        lastMessageAt: directMessages.last.createdAt,
        members: [
          me,
          ConversationMember(
            userId: 'demo-friend-1',
            role: ConversationRole.member,
            displayName: 'Аня',
            emoji: '🌸',
          ),
        ],
        lastMessage: directMessages.last,
        unreadCount: 1,
        hasActiveSignal: true,
      ),
    );
    await _saveConversation(
      ConversationSummary(
        id: 'demo-group-close',
        type: ConversationType.group,
        title: 'Свои',
        ownerId: 'demo-friend-1',
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: groupMessages.last.createdAt,
        lastMessageAt: groupMessages.last.createdAt,
        role: ConversationRole.member,
        members: [
          me,
          ConversationMember(
            userId: 'demo-friend-1',
            role: ConversationRole.owner,
            displayName: 'Аня',
            emoji: '🌸',
          ),
          ConversationMember(
            userId: 'demo-friend-2',
            role: ConversationRole.member,
            displayName: 'Миша',
            emoji: '🛸',
          ),
        ],
        lastMessage: groupMessages.last,
      ),
    );
    await _cache.writeSetting('demo.messenger.seeded.v1', 'true');
  }

  Future<List<ConversationSummary>> _cachedConversations() async {
    final viewerId = await currentUserId();
    return (await _cache.cachedConversations())
        .map(
          (row) => _conversationForViewer(
            ConversationSummary.fromJson(
              jsonDecode(row) as Map<String, dynamic>,
            ),
            viewerId,
          ),
        )
        .toList();
  }

  Future<MessagePage> _cachedMessagePage(
    String conversationId, {
    String? cursor,
    int limit = 30,
  }) async {
    final before = int.tryParse(cursor ?? '');
    final rows = await _cache.cachedMessages(
      conversationId,
      limit: limit + 1,
      beforeEpochMs: before,
    );
    final hasMore = rows.length > limit;
    final viewerId = await currentUserId();
    final messages = rows
        .take(limit)
        .map(
          (row) => ChatMessage.fromJson(
            jsonDecode(row) as Map<String, dynamic>,
          ).normalizeDeliveryForViewer(viewerId),
        )
        .toList();
    return MessagePage(
      items: messages,
      nextCursor: hasMore && messages.isNotEmpty
          ? messages.last.createdAt.millisecondsSinceEpoch.toString()
          : null,
    );
  }

  Future<ConversationPage> _conversationPage(dynamic raw) async {
    final envelope = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{'items': raw};
    final rows = envelope['items'] as List<dynamic>? ?? const [];
    final viewerId = await currentUserId();
    return ConversationPage(
      items: rows
          .whereType<Map>()
          .map(
            (row) => _conversationForViewer(
              ConversationSummary.fromJson(Map<String, dynamic>.from(row)),
              viewerId,
            ),
          )
          .toList(),
      nextCursor: envelope['nextCursor'] as String?,
    );
  }

  Future<MessagePage> _messagePage(dynamic raw) async {
    final envelope = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{'items': raw};
    final rows = envelope['items'] as List<dynamic>? ?? const [];
    final viewerId = await currentUserId();
    return MessagePage(
      items: rows
          .whereType<Map>()
          .map(
            (row) => ChatMessage.fromJson(
              Map<String, dynamic>.from(row),
            ).normalizeDeliveryForViewer(viewerId),
          )
          .toList(),
      nextCursor: envelope['nextCursor'] as String?,
    );
  }

  ConversationSummary _conversationForViewer(
    ConversationSummary conversation,
    String viewerId,
  ) {
    final lastMessage = conversation.lastMessage;
    if (lastMessage == null) return conversation;
    return conversation.copyWith(
      lastMessage: lastMessage.normalizeDeliveryForViewer(viewerId),
    );
  }

  Future<void> _saveConversation(ConversationSummary conversation) =>
      _cache.cacheConversation(
        conversation.id,
        jsonEncode(conversation.toJson()),
        updatedAt: conversation.lastMessageAt ?? conversation.updatedAt,
      );

  Future<void> _saveMessage(ChatMessage message) => _cache.cacheMessage(
    id: message.id,
    conversationId: message.conversationId,
    payload: jsonEncode(message.toJson()),
    createdAt: message.createdAt,
  );

  Future<void> _updateConversationWithMessage(ChatMessage message) async {
    final cached = await _cache.cachedConversation(message.conversationId);
    if (cached == null) return;
    final conversation = ConversationSummary.fromJson(
      jsonDecode(cached) as Map<String, dynamic>,
    );
    await _saveConversation(
      conversation.copyWith(
        updatedAt: message.createdAt,
        lastMessageAt: message.createdAt,
        lastMessage: message,
      ),
    );
  }

  void _emitDemoMessage(ChatMessage message) {
    _realtime.emitDemo(
      RealtimeEvent(
        id: 'demo-event-${message.id}',
        sequence: message.createdAt.microsecondsSinceEpoch,
        occurredAt: message.createdAt.toUtc(),
        type: 'message.created',
        payload: {
          'conversationId': message.conversationId,
          'message': message.toJson(),
        },
      ),
    );
  }

  Map<String, dynamic> _requestFor(ChatMessage message) => {
    'clientMessageId': message.clientMessageId,
    'type': switch (message.type) {
      ChatMessageType.storyReply => 'STORY_REPLY',
      _ => message.type.name.toUpperCase(),
    },
    if (message.text != null) 'text': message.text,
    if (message.metadata.isNotEmpty) 'metadata': message.metadata,
    if (message.replyToMessageId != null)
      'replyToMessageId': message.replyToMessageId,
    if (message.forwardedFromMessageId != null)
      'forwardedFromMessageId': message.forwardedFromMessageId,
  };
}

final chatsRepositoryProvider = Provider<ChatsRepository>(
  (ref) => ChatsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localCacheProvider),
    ref.watch(realtimeCoordinatorProvider),
    ref.watch(appConfigProvider).demoMode,
  ),
);

final currentUserIdProvider = FutureProvider<String>(
  (ref) => ref.watch(chatsRepositoryProvider).currentUserId(),
);

final conversationProvider = FutureProvider.family<ConversationSummary, String>(
  (ref, id) => ref.watch(chatsRepositoryProvider).conversation(id),
);

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

bool _isRetryable(DioException error) {
  final status = error.response?.statusCode;
  if (status == null) return true;
  return status == 408 || status == 429 || status >= 500;
}
