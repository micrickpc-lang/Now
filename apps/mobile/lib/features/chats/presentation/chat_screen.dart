import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/chat_controllers.dart';
import '../data/chats_repository.dart';
import '../domain/chat_models.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.conversationId, super.key});
  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  late final ChatsRepository _repository;
  Timer? _draftTimer;
  bool _draftRestored = false;
  bool _sending = false;
  bool _sendingSignal = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(chatsRepositoryProvider);
    _scroll.addListener(_onScroll);
    _composer.addListener(_onComposerChanged);
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 180) {
      unawaited(
        ref
            .read(chatMessagesProvider(widget.conversationId).notifier)
            .loadOlder(),
      );
    }
  }

  void _onComposerChanged() {
    if (!_draftRestored) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 350), () {
      ref
          .read(chatMessagesProvider(widget.conversationId).notifier)
          .saveDraft(_composer.text);
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (_draftRestored) {
      unawaited(_repository.saveDraft(widget.conversationId, _composer.text));
    }
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    _composer.clear();
    setState(() => _sending = true);
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendText(text);
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _sendSignal() async {
    if (_sendingSignal) return;
    final result = await context.push<Map<String, dynamic>>(
      Uri(
        path: '/signal/new',
        queryParameters: {'conversationId': widget.conversationId},
      ).toString(),
    );
    final signalId = result?['id']?.toString();
    if (!mounted || signalId == null || signalId.isEmpty) return;
    setState(() => _sendingSignal = true);
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendSignal(signalId);
    if (mounted) setState(() => _sendingSignal = false);
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(conversationProvider(widget.conversationId));
    final timeline = ref.watch(chatMessagesProvider(widget.conversationId));
    final userId = ref.watch(currentUserIdProvider).value ?? '';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: conversation.when(
          data: (chat) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chat.displayTitle(userId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                chat.type == ConversationType.group
                    ? '${chat.members.length} участника'
                    : 'только для вас двоих',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          loading: () => const Text('Чат'),
          error: (_, __) => const Text('Чат'),
        ),
        actions: [
          IconButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text(
                  'Поиск, закрепление и действия с сообщениями будут добавлены после стабилизации текстовой переписки.',
                ),
              ),
            ),
            tooltip: 'Информация о чате',
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: timeline.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => ref.invalidate(
                    chatMessagesProvider(widget.conversationId),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Повторить загрузку'),
                ),
              ),
              data: (data) {
                if (!_draftRestored) {
                  _draftRestored = true;
                  _composer.text = data.draft;
                  _composer.selection = TextSelection.collapsed(
                    offset: _composer.text.length,
                  );
                }
                if (data.messages.isEmpty) {
                  return const _EmptyChat();
                }
                return ListView.builder(
                  key: const PageStorageKey('chat-messages'),
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                  itemCount: data.messages.length + (data.loadingOlder ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == data.messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final message = data.messages[index];
                    final older = index + 1 < data.messages.length
                        ? data.messages[index + 1]
                        : null;
                    final showDate =
                        older == null ||
                        !DateUtils.isSameDay(
                          message.createdAt,
                          older.createdAt,
                        );
                    return Column(
                      children: [
                        if (showDate)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _DateLabel(value: message.createdAt),
                          ),
                        _MessageBubble(
                          message: message,
                          outgoing: message.senderId == userId,
                          onOpenSignal: () => context.go('/now'),
                          onRetry: () => ref
                              .read(
                                chatMessagesProvider(
                                  widget.conversationId,
                                ).notifier,
                              )
                              .retry(message),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      key: const ValueKey('send-signal'),
                      onPressed: _sendingSignal ? null : _sendSignal,
                      tooltip: 'Создать сигнал в чате',
                      icon: _sendingSignal
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt_rounded),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('message-composer'),
                        controller: _composer,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: 'Сообщение',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const ValueKey('send-message'),
                      onPressed: _sending ? null : _send,
                      tooltip: 'Отправить сообщение',
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.outgoing,
    required this.onOpenSignal,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool outgoing;
  final VoidCallback onOpenSignal;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Align(
    alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
    child: GestureDetector(
      onLongPress: message.text == null
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: message.text!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Сообщение скопировано')),
                );
              }
            },
      child: Container(
        key: ValueKey('message-${message.id}'),
        margin: EdgeInsets.only(
          bottom: 5,
          left: outgoing ? 54 : 0,
          right: outgoing ? 0 : 54,
        ),
        padding: const EdgeInsets.fromLTRB(13, 9, 10, 7),
        decoration: BoxDecoration(
          color: outgoing
              ? AppColors.mint.withValues(alpha: .18)
              : Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child:
                  message.deletedAt == null &&
                      message.type == ChatMessageType.signal
                  ? _SignalMessageContent(onOpen: onOpenSignal)
                  : Text(
                      message.deletedAt == null
                          ? message.text ?? 'Неподдерживаемое сообщение'
                          : 'Сообщение удалено',
                      style: TextStyle(
                        fontStyle: message.deletedAt == null
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (outgoing) ...[
              const SizedBox(width: 3),
              _DeliveryIcon(message: message, onRetry: onRetry),
            ],
          ],
        ),
      ),
    ),
  );
}

class _SignalMessageContent extends StatelessWidget {
  const _SignalMessageContent({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 170),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 19, color: AppColors.mint),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Сигнал для участников чата',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        TextButton(
          onPressed: onOpen,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Открыть во вкладке «Сейчас»'),
        ),
      ],
    ),
  );
}

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.message, required this.onRetry});
  final ChatMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = message.deliveryStatus == MessageDeliveryStatus.failed;
    return InkWell(
      onTap: failed ? onRetry : null,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          switch (message.deliveryStatus) {
            MessageDeliveryStatus.pending => Icons.schedule_rounded,
            MessageDeliveryStatus.failed => Icons.refresh_rounded,
            MessageDeliveryStatus.sent => Icons.check_rounded,
            MessageDeliveryStatus.delivered ||
            MessageDeliveryStatus.read => Icons.done_all_rounded,
          },
          size: 15,
          color: message.deliveryStatus == MessageDeliveryStatus.read
              ? AppColors.mint
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.value});
  final DateTime value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        DateUtils.isSameDay(value, DateTime.now())
            ? 'Сегодня'
            : '${value.day} ${const ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'][value.month - 1]}',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 42),
          const SizedBox(height: 14),
          Text(
            'Начните разговор',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'История этого чата останется доступна только его участникам.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
