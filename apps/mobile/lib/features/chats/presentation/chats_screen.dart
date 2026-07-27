import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/realtime_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_controllers.dart';
import '../data/chats_repository.dart';
import '../domain/chat_models.dart';

enum _ChatFilter { all, direct, group, room }

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final _search = TextEditingController();
  var _filter = _ChatFilter.all;
  var _searchVisible = false;

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
            onPressed: () => setState(() => _searchVisible = !_searchVisible),
            tooltip: _searchVisible ? 'Закрыть поиск' : 'Поиск по чатам',
            icon: Icon(
              _searchVisible ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
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
            const _OfflineBanner(
              text: 'Нет интернета. Черновики и сообщения сохранятся.',
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _ChatFilter.values) ...[
                    _ChatFilterChip(
                      filter: filter,
                      selected: _filter == filter,
                      onSelected: () => setState(() => _filter = filter),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                key: const ValueKey('chat-search'),
                controller: _search,
                autofocus: true,
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
                          (chat) => switch (_filter) {
                            _ChatFilter.all => true,
                            _ChatFilter.direct =>
                              chat.type == ConversationType.direct,
                            _ChatFilter.group =>
                              chat.type == ConversationType.group &&
                                  !chat.hasActiveSignal,
                            _ChatFilter.room =>
                              chat.type == ConversationType.group &&
                                  chat.hasActiveSignal,
                          },
                        )
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
                  child: ListView.builder(
                    key: const PageStorageKey('chats-list'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => Padding(
                      padding: EdgeInsets.only(
                        bottom: index == visible.length - 1 ? 0 : 8,
                      ),
                      child: _ChatTile(
                        conversation: visible[index],
                        currentUserId: currentUserId,
                      ),
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
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        key: ValueKey('chat-${conversation.id}'),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          onTap: () => context.push('/chats/${conversation.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _ChatAvatar(
                      emoji: conversation.displayEmoji(currentUserId),
                    ),
                    if (conversation.hasActiveSignal)
                      const Positioned(
                        right: -2,
                        bottom: -2,
                        child: _ActivityMark(),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.displayTitle(currentUserId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (last?.senderId == currentUserId) ...[
                            _MessageStatus(status: last!.deliveryStatus),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              conversation.isTyping
                                  ? 'печатает...'
                                  : _messagePreview(last),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: conversation.isTyping
                                    ? AppColors.mint
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (conversation.hasActiveCall)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.call_outlined, size: 17),
                            ),
                          if (conversation.unreadCount > 0)
                            _UnreadBadge(count: conversation.unreadCount),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.violet.withValues(alpha: .22),
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.mint, width: 1.5),
    ),
    child: Text(emoji, style: const TextStyle(fontSize: 21)),
  );
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 8),
    constraints: const BoxConstraints(minWidth: 20),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: const BoxDecoration(
      color: AppColors.coral,
      shape: BoxShape.circle,
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ChatFilterChip extends StatelessWidget {
  const _ChatFilterChip({
    required this.filter,
    required this.selected,
    required this.onSelected,
  });

  final _ChatFilter filter;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(switch (filter) {
      _ChatFilter.all => 'Все',
      _ChatFilter.direct => 'Личные',
      _ChatFilter.group => 'Группы',
      _ChatFilter.room => 'Комнаты',
    }),
    selected: selected,
    onSelected: (_) => onSelected(),
    showCheckmark: false,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      border: Border.all(color: AppColors.warning.withValues(alpha: .75)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 18,
          color: AppColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
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
