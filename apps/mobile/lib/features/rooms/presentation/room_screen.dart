import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/realtime_client.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../map/domain/map_models.dart';
import '../data/room_location_share_coordinator.dart';
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
  Future<List<RoomLocationShare>>? _locationShares;
  StreamSubscription<RealtimeEvent>? _events;
  RealtimeLease? _roomLease;

  @override
  void initState() {
    super.initState();
    _reload();
    Future.microtask(() {
      final realtime = ref.read(realtimeCoordinatorProvider);
      _roomLease = realtime.subscribeRoom(widget.roomId);
      _events = realtime.events
          .where((event) {
            final roomId = event.payload['roomId']?.toString();
            return (roomId == null || roomId == widget.roomId) &&
                (event.type == 'room.message.created' ||
                    event.type == 'location.share.updated' ||
                    event.type == 'location.share.revoked' ||
                    event.type == 'room.completed');
          })
          .listen((event) {
            if (event.type == 'room.completed') {
              unawaited(_roomCompleted());
            } else if (mounted) {
              _reload();
            }
          });
    });
  }

  void _reload() {
    final rooms = ref.read(roomsRepositoryProvider);
    final exactEnabled = ref.read(appConfigProvider).canShareExactLocation;
    setState(() {
      _room = rooms.room(widget.roomId);
      _messages = rooms.messages(widget.roomId);
      _locationShares = exactEnabled
          ? rooms.locationShares(widget.roomId)
          : Future.value(const <RoomLocationShare>[]);
    });
  }

  @override
  void dispose() {
    final share = ref.read(roomLocationShareCoordinatorProvider);
    if (share.activeRoomId == widget.roomId) unawaited(share.stop());
    _events?.cancel();
    _roomLease?.close();
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
    if (!ref.read(appConfigProvider).canShareExactLocation) return;
    final result = await context.push<MapSelectionResult>(
      '/map',
      extra: const PlacePickerRequest.exactRoom(),
    );
    if (result == null || !mounted || result.sourcePoint == null) return;
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
      try {
        await ref
            .read(roomLocationShareCoordinatorProvider)
            .start(widget.roomId, result);
        await SecureScreen.enable();
        _reload();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось включить геопозицию')),
          );
        }
      }
    }
  }

  Future<void> _revokeLocation() async {
    try {
      await ref
          .read(roomLocationShareCoordinatorProvider)
          .stop(suppressRevokeErrors: false);
      await SecureScreen.disable();
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS остановлен, но сервер не подтвердил отзыв. Повтори действие.',
          ),
        ),
      );
    }
  }

  Future<void> _leaveRoom() async {
    await ref.read(roomLocationShareCoordinatorProvider).stop(revoke: false);
    await ref.read(roomsRepositoryProvider).leave(widget.roomId);
    if (mounted) context.go('/now');
  }

  Future<void> _roomCompleted() async {
    await ref.read(roomLocationShareCoordinatorProvider).stop(revoke: false);
    await SecureScreen.disable();
    if (mounted) context.go('/now');
  }

  Future<void> _openLocation(RoomLocationShare share) async {
    final latitude = share.latitude;
    final longitude = share.longitude;
    if (latitude == null || longitude == null) return;
    await SecureScreen.enable();
    if (!mounted) return;
    await context.push<void>(
      '/map',
      extra: PlacePickerRequest.viewExact(
        point: GeoPoint(latitude, longitude),
        label: share.label,
      ),
    );
    if (mounted &&
        ref.read(roomLocationShareCoordinatorProvider).activeRoomId !=
            widget.roomId) {
      await SecureScreen.disable();
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
              await _leaveRoom();
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
        FutureBuilder<List<RoomLocationShare>>(
          future: _locationShares,
          builder: (context, snapshot) {
            final ownShare =
                ref.read(roomLocationShareCoordinatorProvider).activeRoomId ==
                widget.roomId;
            final hasShares = ownShare || (snapshot.data?.isNotEmpty ?? false);
            final exactEnabled = ref
                .watch(appConfigProvider)
                .canShareExactLocation;
            RoomLocationShare? visibleShare;
            for (final share in snapshot.data ?? const <RoomLocationShare>[]) {
              if (share.latitude != null && share.longitude != null) {
                visibleShare = share;
                break;
              }
            }
            return AnimatedSwitcher(
              duration: AppDuration.normal,
              child: !hasShares
                  ? Material(
                      color: AppColors.violet.withValues(alpha: .12),
                      child: ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: const Text('Место ещё не выбрано'),
                        subtitle: Text(
                          exactEnabled
                              ? 'Точная точка — только с явным согласием'
                              : 'Отключено для небезопасного HTTP staging',
                        ),
                        trailing: TextButton(
                          onPressed: exactEnabled ? _shareLocation : null,
                          child: const Text('Выбрать'),
                        ),
                      ),
                    )
                  : Material(
                      color: AppColors.mint.withValues(alpha: .12),
                      child: ListTile(
                        onTap: visibleShare == null
                            ? null
                            : () => _openLocation(visibleShare!),
                        leading: const Icon(
                          Icons.shield_rounded,
                          color: AppColors.mint,
                        ),
                        title: const Text('Точное место доступно участникам'),
                        subtitle: const Text(
                          'Скриншоты на этом экране ограничены',
                        ),
                        trailing: ownShare
                            ? TextButton(
                                onPressed: _revokeLocation,
                                child: const Text('Отозвать'),
                              )
                            : visibleShare == null
                            ? null
                            : const Icon(Icons.chevron_right_rounded),
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
                  onPressed: ref.watch(appConfigProvider).canShareExactLocation
                      ? _shareLocation
                      : null,
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
