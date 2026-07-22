import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/config/app_config.dart';
import 'package:seychas/core/storage/local_cache.dart';
import 'package:seychas/features/chats/data/chats_repository.dart';
import 'package:seychas/features/chats/domain/chat_models.dart';

void main() {
  test(
    'demo direct/group chats, messages and draft survive ProviderScope restart',
    () async {
      final cache = LocalCache.forTest(NativeDatabase.memory());
      final first = _container(cache);
      final repository = first.read(chatsRepositoryProvider);

      final seeded = await repository.conversations();
      expect(
        seeded.items.where((chat) => chat.type == ConversationType.direct),
        isNotEmpty,
      );
      expect(
        seeded.items.where((chat) => chat.type == ConversationType.group),
        isNotEmpty,
      );

      final pending = await repository.createPendingText(
        'demo-direct-anya',
        'Сообщение после перезапуска',
      );
      final delivered = await repository.deliverPending(pending);
      expect(delivered.deliveryStatus, MessageDeliveryStatus.delivered);
      await repository.saveDraft('demo-direct-anya', 'Сохранённый черновик');
      expect(await cache.outbox(), isEmpty);
      first.dispose();
      await Future<void>.delayed(Duration.zero);

      final afterRestart = _container(cache);
      final restoredRepository = afterRestart.read(chatsRepositoryProvider);
      final messages = await restoredRepository.messages('demo-direct-anya');
      expect(
        messages.items.map((message) => message.text),
        contains('Сообщение после перезапуска'),
      );
      expect(
        await restoredRepository.draft('demo-direct-anya'),
        'Сохранённый черновик',
      );

      final newDirect = await restoredRepository.createDirect(
        friendId: 'demo-friend-3',
        displayName: 'Лера',
        emoji: '☀️',
      );
      expect(newDirect.type, ConversationType.direct);
      final newGroup = await restoredRepository.createGroup(
        title: 'Выходные',
        members: const [
          ConversationMember(
            userId: 'demo-friend-3',
            role: ConversationRole.member,
            displayName: 'Лера',
            emoji: '☀️',
          ),
        ],
      );
      expect(newGroup.type, ConversationType.group);

      afterRestart.dispose();
      await Future<void>.delayed(Duration.zero);
      await cache.close();
    },
  );
}

ProviderContainer _container(LocalCache cache) => ProviderContainer(
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
    localCacheProvider.overrideWithValue(cache),
  ],
);
