import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/realtime_client.dart';
import '../domain/chat_models.dart';
import 'chats_repository.dart';

class ChatsController extends AsyncNotifier<List<ConversationSummary>> {
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<RealtimeConnectionStatus>? _statuses;
  bool _initializing = false;
  bool _processingReconciliation = false;
  bool _outboxDrainRequested = false;
  bool _refreshRequested = false;

  @override
  Future<List<ConversationSummary>> build() async {
    _initializing = true;
    try {
      _events ??= ref.read(realtimeCoordinatorProvider).events.listen((event) {
        if (event.type.startsWith('conversation.') ||
            event.type.startsWith('message.') ||
            event.type.startsWith('typing.')) {
          unawaited(refresh(silent: true));
        }
      });
      _statuses ??= ref
          .read(realtimeCoordinatorProvider)
          .statuses
          .where(
            (status) =>
                status == RealtimeConnectionStatus.connected ||
                status == RealtimeConnectionStatus.demo,
          )
          .listen((_) => _requestReconciliation(refresh: true));
      ref.onDispose(() {
        unawaited(_events?.cancel());
        unawaited(_statuses?.cancel());
      });
      _requestReconciliation(refresh: false);
      return (await ref.watch(chatsRepositoryProvider).conversations()).items;
    } finally {
      _initializing = false;
      if (_outboxDrainRequested || _refreshRequested) {
        Timer.run(_startReconciliation);
      }
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () async =>
          (await ref.read(chatsRepositoryProvider).conversations()).items,
    );
    if (next.hasValue || !silent) state = next;
  }

  void _requestReconciliation({required bool refresh}) {
    _outboxDrainRequested = true;
    _refreshRequested = _refreshRequested || refresh;
    _startReconciliation();
  }

  void _startReconciliation() {
    if (_initializing ||
        _processingReconciliation ||
        !ref.mounted ||
        (!_outboxDrainRequested && !_refreshRequested)) {
      return;
    }
    _processingReconciliation = true;
    unawaited(_runReconciliation());
  }

  Future<void> _runReconciliation() async {
    try {
      while (ref.mounted && (_outboxDrainRequested || _refreshRequested)) {
        final shouldRefresh = _refreshRequested;
        _outboxDrainRequested = false;
        _refreshRequested = false;
        var outboxChanged = false;
        try {
          outboxChanged =
              (await ref.read(chatsRepositoryProvider).retryAllOutbox())
                  .isNotEmpty;
        } catch (_) {
          // Reconciliation still refreshes server state when outbox retry fails.
        }
        if ((shouldRefresh || outboxChanged) && ref.mounted) {
          await refresh(silent: true);
        }
      }
    } finally {
      _processingReconciliation = false;
      _startReconciliation();
    }
  }
}

final chatsProvider =
    AsyncNotifierProvider<ChatsController, List<ConversationSummary>>(
      ChatsController.new,
    );

class ChatTimeline {
  const ChatTimeline({
    required this.messages,
    required this.draft,
    this.nextCursor,
    this.loadingOlder = false,
  });

  final List<ChatMessage> messages;
  final String draft;
  final String? nextCursor;
  final bool loadingOlder;

  ChatTimeline copyWith({
    List<ChatMessage>? messages,
    String? draft,
    String? nextCursor,
    bool? loadingOlder,
    bool clearCursor = false,
  }) => ChatTimeline(
    messages: messages ?? this.messages,
    draft: draft ?? this.draft,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    loadingOlder: loadingOlder ?? this.loadingOlder,
  );
}

class ChatMessagesController extends AsyncNotifier<ChatTimeline> {
  ChatMessagesController(this.conversationId);

  final String conversationId;
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<RealtimeConnectionStatus>? _statuses;
  RealtimeLease? _lease;
  bool _initializing = false;
  bool _processingReconciliation = false;
  bool _reconciliationRequested = false;

  @override
  Future<ChatTimeline> build() async {
    _initializing = true;
    try {
      final repository = ref.watch(chatsRepositoryProvider);
      final coordinator = ref.read(realtimeCoordinatorProvider);
      _lease ??= coordinator.subscribeConversation(conversationId);
      _events ??= coordinator.events
          .where(
            (event) =>
                event.payload['conversationId']?.toString() == conversationId,
          )
          .listen((event) => unawaited(_onRealtime(event)));
      _statuses ??= coordinator.statuses
          .where(
            (status) =>
                status == RealtimeConnectionStatus.connected ||
                status == RealtimeConnectionStatus.demo,
          )
          .listen((_) => _requestReconciliation());
      ref.onDispose(() {
        _lease?.close();
        unawaited(_events?.cancel());
        unawaited(_statuses?.cancel());
      });
      await repository.retryOutbox(conversationId);
      final page = await repository.messages(conversationId);
      final timeline = ChatTimeline(
        messages: page.items,
        nextCursor: page.nextCursor,
        draft: await repository.draft(conversationId),
      );
      unawaited(_markNewestRead(timeline.messages));
      return timeline;
    } finally {
      _initializing = false;
      if (_reconciliationRequested) {
        Timer.run(_startReconciliation);
      }
    }
  }

  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || current.loadingOlder || current.nextCursor == null) {
      return;
    }
    state = AsyncData(current.copyWith(loadingOlder: true));
    try {
      final page = await ref
          .read(chatsRepositoryProvider)
          .messages(conversationId, cursor: current.nextCursor);
      state = AsyncData(
        current.copyWith(
          messages: _merge(current.messages, page.items),
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          loadingOlder: false,
        ),
      );
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  Future<void> sendText(String text) async {
    final body = text.trim();
    final current = state.value;
    if (body.isEmpty || current == null) return;
    final repository = ref.read(chatsRepositoryProvider);
    final pending = await repository.createPendingText(conversationId, body);
    state = AsyncData(
      current.copyWith(
        messages: _merge([pending], current.messages),
        draft: '',
      ),
    );
    await repository.saveDraft(conversationId, '');
    final delivered = await repository.deliverPending(pending);
    final latest = state.value;
    if (latest != null) {
      state = AsyncData(
        latest.copyWith(
          messages: _replaceByClientId(latest.messages, delivered),
        ),
      );
    }
    ref.invalidate(chatsProvider);
  }

  Future<void> sendSignal(String signalId) async {
    final current = state.value;
    if (signalId.isEmpty || current == null) return;
    final repository = ref.read(chatsRepositoryProvider);
    final pending = await repository.createPendingSignal(
      conversationId,
      signalId,
    );
    state = AsyncData(
      current.copyWith(messages: _merge([pending], current.messages)),
    );
    final delivered = await repository.deliverPending(pending);
    final latest = state.value;
    if (latest != null) {
      state = AsyncData(
        latest.copyWith(
          messages: _replaceByClientId(latest.messages, delivered),
        ),
      );
    }
    ref.invalidate(chatsProvider);
  }

  Future<void> retry(ChatMessage message) async {
    if (message.deliveryStatus != MessageDeliveryStatus.failed) return;
    final delivered = await ref
        .read(chatsRepositoryProvider)
        .deliverPending(
          message.copyWith(deliveryStatus: MessageDeliveryStatus.pending),
        );
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          messages: _replaceByClientId(current.messages, delivered),
        ),
      );
    }
    ref.invalidate(chatsProvider);
  }

  Future<void> saveDraft(String value) async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(draft: value));
    }
    await ref.read(chatsRepositoryProvider).saveDraft(conversationId, value);
  }

  Future<void> _onRealtime(RealtimeEvent event) async {
    final repository = ref.read(chatsRepositoryProvider);
    final message = await repository.applyRealtime(event);
    if (message != null) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(
          current.copyWith(messages: _merge([message], current.messages)),
        );
        await _markNewestRead([message]);
      }
    } else if (event.type == 'message.delivered') {
      final messageId = event.payload['messageId']?.toString();
      final current = state.value;
      if (messageId != null && current != null) {
        ChatMessage? delivered;
        final messages = [
          for (final item in current.messages)
            if (item.id == messageId)
              delivered = item.markDelivered()
            else
              item,
        ];
        state = AsyncData(current.copyWith(messages: messages));
        if (delivered != null) await repository.persistRealtimeState(delivered);
      }
    } else if (event.type == 'message.read' ||
        event.type == 'message.updated' ||
        event.type == 'message.deleted') {
      final page = await repository.messages(conversationId);
      final current = state.value;
      if (current != null) {
        state = AsyncData(
          current.copyWith(
            messages: _merge(page.items, current.messages),
            nextCursor: page.nextCursor,
            clearCursor: page.nextCursor == null,
          ),
        );
      }
    }
    ref.invalidate(chatsProvider);
  }

  void _requestReconciliation() {
    _reconciliationRequested = true;
    _startReconciliation();
  }

  void _startReconciliation() {
    if (_initializing ||
        _processingReconciliation ||
        !_reconciliationRequested ||
        !ref.mounted) {
      return;
    }
    _processingReconciliation = true;
    unawaited(_runReconciliation());
  }

  Future<void> _runReconciliation() async {
    try {
      while (ref.mounted && _reconciliationRequested) {
        _reconciliationRequested = false;
        final repository = ref.read(chatsRepositoryProvider);
        var retried = const <ChatMessage>[];
        MessagePage? page;
        try {
          retried = await repository.retryOutbox(conversationId);
        } catch (_) {
          // A failed send must not prevent the gap-closing page refresh.
        }
        if (!ref.mounted) return;
        try {
          page = await repository.messages(conversationId);
        } catch (_) {
          // Cached/current state remains usable until the next reconciliation.
        }
        if (!ref.mounted) return;
        final current = state.value;
        if (current != null && (page != null || retried.isNotEmpty)) {
          state = AsyncData(
            current.copyWith(
              messages: _merge([...?page?.items, ...retried], current.messages),
            ),
          );
        }
        if (page != null) {
          await _markNewestRead(page.items);
        }
        if (ref.mounted) ref.invalidate(chatsProvider);
      }
    } finally {
      _processingReconciliation = false;
      _startReconciliation();
    }
  }

  Future<void> _markNewestRead(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    try {
      final repository = ref.read(chatsRepositoryProvider);
      final currentUserId = await repository.currentUserId();
      ChatMessage? newestIncoming;
      for (final message in messages) {
        if (message.senderId != null && message.senderId != currentUserId) {
          newestIncoming = message;
          break;
        }
      }
      if (newestIncoming == null) return;
      await repository.markRead(newestIncoming);
      ref.invalidate(chatsProvider);
    } catch (_) {
      // Read receipts are safe to retry when the next realtime/page refresh runs.
    }
  }
}

final chatMessagesProvider = AsyncNotifierProvider.family
    .autoDispose<ChatMessagesController, ChatTimeline, String>(
      ChatMessagesController.new,
    );

List<ChatMessage> _merge(
  Iterable<ChatMessage> preferred,
  Iterable<ChatMessage> existing,
) {
  final byKey = <String, ChatMessage>{};
  for (final message in [...existing, ...preferred]) {
    byKey[message.clientMessageId ?? message.id] = message;
  }
  final result = byKey.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return result;
}

List<ChatMessage> _replaceByClientId(
  List<ChatMessage> messages,
  ChatMessage replacement,
) => _merge(
  [replacement],
  messages.where(
    (message) =>
        message.id != replacement.id &&
        (replacement.clientMessageId == null ||
            message.clientMessageId != replacement.clientMessageId),
  ),
);
