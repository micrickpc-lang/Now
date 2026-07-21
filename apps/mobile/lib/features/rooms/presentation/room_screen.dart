import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/realtime_client.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../data/rooms_repository.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({required this.roomId, super.key});
  final String roomId;
  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final _message = TextEditingController();
  Future<Map<String, dynamic>>? _room;
  Future<List<Map<String, dynamic>>>? _messages;
  StreamSubscription<Map<String, dynamic>>? _events;

  @override
  void initState() {
    super.initState();
    _reload();
    Future.microtask(() {
      final realtime = ref.read(realtimeClientProvider);
      realtime.subscribeRoom(widget.roomId);
      _events = realtime.events
          .where((event) {
            final type = event['type'];
            return type == 'room.message.created' ||
                type == 'location.share.updated' ||
                type == 'location.share.revoked';
          })
          .listen((_) {
            if (mounted) _reload();
          });
    });
  }

  void _reload() => setState(() {
    _room = ref.read(roomsRepositoryProvider).room(widget.roomId);
    _messages = ref.read(roomsRepositoryProvider).messages(widget.roomId);
  });

  @override
  void dispose() {
    _events?.cancel();
    _message.dispose();
    SecureScreen.disable();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    _message.clear();
    await ref.read(roomsRepositoryProvider).send(widget.roomId, text);
    _reload();
  }

  Future<void> _shareLocation() async {
    final result = await context.push<Map<String, double>>('/map');
    if (result == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.location_on_rounded),
        title: const Text('Поделиться точным местом?'),
        content: const Text(
          'Только участники этой комнаты увидят точку. Она удалится через 30 минут или сразу после отзыва, выхода или завершения комнаты.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Не сейчас'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Поделиться'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SecureScreen.enable();
      await ref
          .read(roomsRepositoryProvider)
          .share(
            widget.roomId,
            latitude: result['latitude']!,
            longitude: result['longitude']!,
          );
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: FutureBuilder<Map<String, dynamic>>(
        future: _room,
        builder: (_, snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(snapshot.data?['title']?.toString() ?? 'Временная комната'),
            const Text(
              'исчезнет по завершении',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'leave') {
              await ref.read(roomsRepositoryProvider).leave(widget.roomId);
              if (context.mounted) context.go('/');
            } else if (value == 'report') {
              context.push('/report');
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'report', child: Text('Пожаловаться')),
            PopupMenuItem(value: 'leave', child: Text('Выйти из комнаты')),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _room,
          builder: (context, snapshot) {
            final shares =
                (snapshot.data?['locationShares'] as List<dynamic>?) ??
                const [];
            return AnimatedSwitcher(
              duration: AppDuration.normal,
              child: shares.isEmpty
                  ? Material(
                      color: AppColors.violet.withValues(alpha: .12),
                      child: ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: const Text('Место ещё не выбрано'),
                        subtitle: const Text(
                          'Точная точка — только с явным согласием',
                        ),
                        trailing: TextButton(
                          onPressed: _shareLocation,
                          child: const Text('Выбрать'),
                        ),
                      ),
                    )
                  : Material(
                      color: AppColors.mint.withValues(alpha: .12),
                      child: ListTile(
                        leading: const Icon(
                          Icons.shield_rounded,
                          color: AppColors.mint,
                        ),
                        title: const Text('Точное место доступно участникам'),
                        subtitle: const Text(
                          'Скриншоты на этом экране ограничены',
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            await ref
                                .read(roomsRepositoryProvider)
                                .revoke(widget.roomId);
                            await SecureScreen.disable();
                            _reload();
                          },
                          child: const Text('Отозвать'),
                        ),
                      ),
                    ),
            );
          },
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _messages,
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!.reversed.toList();
              if (rows.isEmpty)
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('💬', style: TextStyle(fontSize: 52)),
                      SizedBox(height: 12),
                      Text('Договоритесь о деталях'),
                      Text(
                        'Комната не станет бесконечным чатом',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                );
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .78,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(row['body'] as String),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: _shareLocation,
                  tooltip: 'Поделиться точным местом',
                  icon: const Icon(Icons.add_location_alt_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _message,
                    maxLength: 1000,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'Сообщение участникам',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  tooltip: 'Отправить',
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
