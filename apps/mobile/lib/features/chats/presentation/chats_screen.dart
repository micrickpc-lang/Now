import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/realtime_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_controllers.dart';
import '../data/chats_repository.dart';
import '../domain/chat_models.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final currentUserId = ref.watch(currentUserIdProvider).value ?? '';
    final realtimeStatus = ref.watch(realtimeStatusProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(
            onPressed: () => ref.read(chatsProvider.notifier).refresh(),
            tooltip: 'Обновить чаты',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (realtimeStatus == RealtimeConnectionStatus.offline)
            const Material(
              color: Color(0x1929D3A2),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.cloud_off_outlined, size: 20),
                title: Text('Без сети · сообщения останутся в очереди'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              key: const ValueKey('chat-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Поиск по чатам',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: chats.when(
              loading: () => const _ChatsSkeleton(),
              error: (error, _) => _ChatsError(
                onRetry: () => ref.read(chatsProvider.notifier).refresh(),
              ),
              data: (items) {
                final query = _search.text.trim().toLowerCase();
                final visible =
                    items
                        .where((chat) => !chat.isArchived)
                        .where(
                          (chat) =>
                              query.isEmpty ||
                              chat
                                  .displayTitle(currentUserId)
                                  .toLowerCase()
                                  .contains(query) ||
                              (chat.lastMessage?.text ?? '')
                                  .toLowerCase()
                                  .contains(query),
                        )
                        .toList()
                      ..sort((a, b) {
                        if (a.isPinned != b.isPinned)
                          return a.isPinned ? -1 : 1;
                        final left = a.lastMessageAt ?? a.updatedAt;
                        final right = b.lastMessageAt ?? b.updatedAt;
                        return right.compareTo(left);
                      });
                if (visible.isEmpty) {
                  return _ChatsEmpty(searching: query.isNotEmpty);
                }
                return RefreshIndicator(
                  onRefresh: ref.read(chatsProvider.notifier).refresh,
                  child: ListView.separated(
                    key: const PageStorageKey('chats-list'),
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 78),
                    itemBuilder: (context, index) => _ChatTile(
                      conversation: visible[index],
                      currentUserId: currentUserId,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.conversation, required this.currentUserId});

  final ConversationSummary conversation;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessage;
    final muted = conversation.mutedUntil?.isAfter(DateTime.now()) ?? false;
    return Semantics(
      button: true,
      label:
          '${conversation.displayTitle(currentUserId)}, ${conversation.unreadCount} непрочитанных',
      child: ListTile(
        key: ValueKey('chat-${conversation.id}'),
        onTap: () => context.push('/chats/${conversation.id}'),
        minVerticalPadding: 13,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              child: Text(
                conversation.displayEmoji(currentUserId),
                style: const TextStyle(fontSize: 22),
              ),
            ),
            if (conversation.hasActiveSignal)
              const Positioned(right: -2, bottom: -2, child: _ActivityMark()),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                conversation.displayTitle(currentUserId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (muted)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.volume_off_outlined, size: 16),
              ),
            const SizedBox(width: 8),
            Text(
              _formatTime(conversation.lastMessageAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              if (last?.senderId == currentUserId) ...[
                _MessageStatus(status: last!.deliveryStatus),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  conversation.isTyping ? 'печатает…' : _messagePreview(last),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: conversation.isTyping
                        ? AppColors.mint
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (conversation.hasActiveCall)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.call_outlined, size: 17),
                ),
              if (conversation.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.mint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    conversation.unreadCount > 99
                        ? '99+'
                        : '${conversation.unreadCount}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF071A15),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityMark extends StatelessWidget {
  const _ActivityMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Theme.of(context).scaffoldBackgroundColor,
      border: Border.all(color: AppColors.mint, width: 2.5),
    ),
    alignment: Alignment.topRight,
    child: const CircleAvatar(radius: 2.2, backgroundColor: AppColors.mint),
  );
}

class _MessageStatus extends StatelessWidget {
  const _MessageStatus({required this.status});
  final MessageDeliveryStatus status;

  @override
  Widget build(BuildContext context) => Icon(
    switch (status) {
      MessageDeliveryStatus.pending => Icons.schedule_rounded,
      MessageDeliveryStatus.failed => Icons.error_outline_rounded,
      MessageDeliveryStatus.sent => Icons.check_rounded,
      MessageDeliveryStatus.delivered ||
      MessageDeliveryStatus.read => Icons.done_all_rounded,
    },
    size: 16,
    color: status == MessageDeliveryStatus.read
        ? AppColors.mint
        : Theme.of(context).colorScheme.onSurfaceVariant,
  );
}

class _ChatsSkeleton extends StatelessWidget {
  const _ChatsSkeleton();

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: 7,
    itemBuilder: (_, __) => const ListTile(
      minVerticalPadding: 14,
      leading: CircleAvatar(backgroundColor: Colors.white10),
      title: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: .55,
        child: LinearProgressIndicator(minHeight: 8),
      ),
    ),
  );
}

class _ChatsEmpty extends StatelessWidget {
  const _ChatsEmpty({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _ActivityMark(),
          const SizedBox(height: 18),
          Text(
            searching ? 'Ничего не найдено' : 'Здесь появятся близкие',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? 'Попробуй другое имя или фразу.'
                : 'Личные и групповые чаты доступны только твоему кругу.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ChatsError extends StatelessWidget {
  const _ChatsError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.tonalIcon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Не удалось загрузить чаты · повторить'),
    ),
  );
}

String _formatTime(DateTime? value) {
  if (value == null) return '';
  final now = DateTime.now();
  if (DateUtils.isSameDay(value, now)) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
  if (now.difference(value).inDays < 7) {
    return const ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'][value.weekday - 1];
  }
  return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${(value.year % 100).toString().padLeft(2, '0')}';
}

String _messagePreview(ChatMessage? message) {
  if (message == null) return 'Сообщений пока нет';
  if (message.deletedAt != null) return 'Сообщение удалено';
  return switch (message.type) {
    ChatMessageType.signal => '⚡ Сигнал в чате',
    ChatMessageType.text => message.text ?? 'Сообщение',
    _ => message.text ?? 'Вложение',
  };
}
