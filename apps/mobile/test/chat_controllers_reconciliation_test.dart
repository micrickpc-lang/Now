import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seychas/core/network/realtime_client.dart';
import 'package:seychas/features/chats/data/chat_controllers.dart';
import 'package:seychas/features/chats/data/chats_repository.dart';
import 'package:seychas/features/chats/domain/chat_models.dart';

class _MockChatsRepository extends Mock implements ChatsRepository {}

class _MockRealtimeCoordinator extends Mock implements RealtimeCoordinator {}

void main() {
  test(
    'authenticated ready refreshes chats when the outbox is empty',
    () async {
      final repository = _MockChatsRepository();
      final coordinator = _MockRealtimeCoordinator();
      final events = StreamController<RealtimeEvent>.broadcast();
      final statuses = StreamController<RealtimeConnectionStatus>.broadcast();
      when(() => coordinator.events).thenAnswer((_) => events.stream);
      when(() => coordinator.statuses).thenAnswer((_) => statuses.stream);

      var conversationCalls = 0;
      var outboxCalls = 0;
      final refreshedConversation = ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.direct,
        createdAt: DateTime.utc(2026, 7, 27),
        updatedAt: DateTime.utc(2026, 7, 27),
      );
      when(() => repository.conversations()).thenAnswer((_) async {
        conversationCalls += 1;
        return ConversationPage(
          items: conversationCalls == 1 ? [] : [refreshedConversation],
        );
      });
      when(() => repository.retryAllOutbox()).thenAnswer((_) async {
        outboxCalls += 1;
        return const <ChatMessage>[];
      });

      final container = ProviderContainer(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          realtimeCoordinatorProvider.overrideWithValue(coordinator),
        ],
      );
      final listener = container.listen(chatsProvider, (_, _) {});
      addTearDown(() async {
        listener.close();
        container.dispose();
        await Future<void>.delayed(Duration.zero);
        await events.close();
        await statuses.close();
      });

      expect(await container.read(chatsProvider.future), isEmpty);
      await _eventually(() => outboxCalls == 1);

      statuses.add(RealtimeConnectionStatus.connected);
      await _eventually(
        () =>
            conversationCalls == 2 &&
            outboxCalls == 2 &&
            container.read(chatsProvider).value?.single.id ==
                refreshedConversation.id,
      );
    },
  );

  test('authenticated ready fetches and merges the newest message page '
      'when the outbox is empty', () async {
    final repository = _MockChatsRepository();
    final coordinator = _MockRealtimeCoordinator();
    final events = StreamController<RealtimeEvent>.broadcast();
    final statuses = StreamController<RealtimeConnectionStatus>.broadcast();
    when(() => coordinator.events).thenAnswer((_) => events.stream);
    when(() => coordinator.statuses).thenAnswer((_) => statuses.stream);
    when(
      () => coordinator.subscribeConversation('conversation-1'),
    ).thenReturn(RealtimeLease(() {}));

    var messageCalls = 0;
    var outboxCalls = 0;
    final refreshedMessage = ChatMessage(
      id: 'message-from-reconciliation',
      conversationId: 'conversation-1',
      type: ChatMessageType.text,
      text: 'latest',
      createdAt: DateTime.utc(2026, 7, 27, 20),
    );
    when(() => repository.retryOutbox('conversation-1')).thenAnswer((_) async {
      outboxCalls += 1;
      return const <ChatMessage>[];
    });
    when(() => repository.messages('conversation-1')).thenAnswer((_) async {
      messageCalls += 1;
      return MessagePage(items: messageCalls == 1 ? [] : [refreshedMessage]);
    });
    when(() => repository.draft('conversation-1')).thenAnswer((_) async => '');

    final container = ProviderContainer(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(repository),
        realtimeCoordinatorProvider.overrideWithValue(coordinator),
      ],
    );
    final provider = chatMessagesProvider('conversation-1');
    final listener = container.listen(provider, (_, _) {});
    addTearDown(() async {
      listener.close();
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      await events.close();
      await statuses.close();
    });

    expect((await container.read(provider.future)).messages, isEmpty);
    expect(messageCalls, 1);
    expect(outboxCalls, 1);

    statuses.add(RealtimeConnectionStatus.connected);
    await _eventually(
      () =>
          messageCalls == 2 &&
          outboxCalls == 2 &&
          container.read(provider).value?.messages.single.id ==
              refreshedMessage.id,
    );
  });
}

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not met before timeout');
}
