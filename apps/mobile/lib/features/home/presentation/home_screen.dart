import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/realtime_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../signals/data/signals_repository.dart';
import '../../signals/domain/signal.dart';
import '../../social/data/social_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _listMode = false;
  StreamSubscription<RealtimeEvent>? _events;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final realtime = ref.read(realtimeCoordinatorProvider);
      _events = realtime.events.listen((event) {
        if (event.type.startsWith('signal.')) {
          ref.read(signalFeedProvider.notifier).refresh();
        }
      });
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(signalFeedProvider);
    final friends = ref.watch(friendsProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Semantics(
            button: true,
            label: 'Открыть профиль',
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.push('/profile'),
              child: const CircleAvatar(
                backgroundColor: AppColors.violet,
                child: Text(
                  'Я',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Твой круг',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              'кто свободен сейчас',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _listMode = !_listMode),
            tooltip: _listMode
                ? 'Показать вселенную'
                : 'Показать доступный список',
            icon: Icon(
              _listMode ? Icons.bubble_chart_rounded : Icons.view_list_rounded,
            ),
          ),
          IconButton(
            onPressed: () => context.push('/circles'),
            tooltip: 'Круги',
            icon: const Icon(Icons.groups_2_outlined),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(.1, -.2),
            radius: 1.15,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: .25),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: feed.when(
            loading: () => const _HomeSkeleton(),
            error: (error, _) => FullScreenError(
              message:
                  'Не удалось загрузить круг. Проверь подключение — сохранённые сигналы появятся автоматически.',
              onRetry: () => ref.read(signalFeedProvider.notifier).refresh(),
            ),
            data: (signals) => RefreshIndicator(
              onRefresh: ref.read(signalFeedProvider.notifier).refresh,
              child: _listMode
                  ? _FriendList(
                      signals: signals,
                      friends: friends.value ?? const [],
                    )
                  : _Universe(
                      signals: signals,
                      friends: friends.value ?? const [],
                    ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Semantics(
        button: true,
        label: 'Создать новый сигнал',
        child: FilledButton.icon(
          onPressed: () async {
            final created = await context.push<bool>('/signal/new');
            if (created == true)
              ref.read(signalFeedProvider.notifier).refresh();
          },
          icon: const Icon(Icons.bolt_rounded),
          label: const Text('Что ты хочешь сейчас?'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            backgroundColor: AppColors.violet,
            foregroundColor: Colors.white,
            elevation: 12,
            shadowColor: AppColors.violet,
          ),
        ),
      ),
    );
  }
}

class _Universe extends StatelessWidget {
  const _Universe({required this.signals, required this.friends});
  final List<SignalModel> signals;
  final List<FriendModel> friends;

  @override
  Widget build(BuildContext context) {
    final nodes = <_Node>[
      ...signals.map(
        (signal) => _Node(
          id: signal.authorId,
          name: signal.authorName,
          emoji:
              signal.emoji ?? signalCategoryLabels[signal.category]?.$2 ?? '✨',
          signal: signal,
        ),
      ),
      ...friends
          .where(
            (friend) => signals.every((signal) => signal.authorId != friend.id),
          )
          .map(
            (friend) => _Node(
              id: friend.id,
              name: friend.name,
              emoji: friend.emoji ?? '🙂',
            ),
          ),
    ].take(16).toList();
    if (nodes.isEmpty)
      return ListView(
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .25),
          const _EmptyCircle(),
        ],
      );
    return InteractiveViewer(
      minScale: .75,
      maxScale: 1.8,
      boundaryMargin: const EdgeInsets.all(160),
      child: SizedBox(
        height: math.max(MediaQuery.sizeOf(context).height - 100, 650),
        width: MediaQuery.sizeOf(context).width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final center = Offset(
              constraints.maxWidth / 2,
              constraints.maxHeight / 2 - 20,
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OrbitPainter(
                      center: center,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Positioned(
                  left: center.dx - 47,
                  top: center.dy - 47,
                  child: const _CenterAvatar(),
                ),
                for (var index = 0; index < nodes.length; index++)
                  _positionNode(
                    context,
                    nodes[index],
                    index,
                    nodes.length,
                    center,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _positionNode(
    BuildContext context,
    _Node node,
    int index,
    int total,
    Offset center,
  ) {
    final ring = index % 3;
    final radius = 128.0 + ring * 72;
    final angle = (index / math.max(total, 1)) * math.pi * 2 + ring * .55;
    final point = Offset(
      center.dx + math.cos(angle) * radius - 37,
      center.dy + math.sin(angle) * radius - 37,
    );
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: _FriendOrb(node: node),
    );
  }
}

class _Node {
  const _Node({
    required this.id,
    required this.name,
    required this.emoji,
    this.signal,
  });
  final String id, name, emoji;
  final SignalModel? signal;
}

class _FriendOrb extends StatelessWidget {
  const _FriendOrb({required this.node});
  final _Node node;
  @override
  Widget build(BuildContext context) {
    final active = node.signal != null;
    return Semantics(
      button: active,
      label: active
          ? '${node.name}: ${signalCategoryLabels[node.signal!.category]?.$1 ?? 'новый сигнал'}'
          : '${node.name}: нет активного сигнала',
      child: GestureDetector(
        onTap: active ? () => _showSignal(context, node.signal!) : null,
        child: AnimatedOpacity(
          duration: AppDuration.normal,
          opacity: active ? 1 : .48,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: active
                      ? const LinearGradient(
                          colors: [AppColors.violet, AppColors.coral],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFF353A50), Color(0xFF272B3D)],
                        ),
                  border: Border.all(
                    color: active ? AppColors.mint : Colors.white12,
                    width: active ? 3 : 1,
                  ),
                  boxShadow: active
                      ? const [
                          BoxShadow(
                            color: Color(0x558B7CFF),
                            blurRadius: 26,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Text(node.emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(height: 5),
              Container(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  node.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _CenterAvatar extends StatelessWidget {
  const _CenterAvatar();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 94,
        height: 94,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x448B7CFF), blurRadius: 32),
          ],
        ),
        child: const Text(
          'Я',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'ты здесь',
        style: TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    ],
  );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.center, required this.color});
  final Offset center;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: .14);
    for (final radius in [128.0, 200.0, 272.0]) {
      canvas.drawCircle(center, radius, paint);
    }
    canvas.drawCircle(
      center,
      320,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .08), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: 320)),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.center != center || old.color != color;
}

class _FriendList extends StatelessWidget {
  const _FriendList({required this.signals, required this.friends});
  final List<SignalModel> signals;
  final List<FriendModel> friends;
  @override
  Widget build(BuildContext context) {
    final activeIds = signals.map((signal) => signal.authorId).toSet();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        if (signals.isNotEmpty) ...[
          const SectionTitle(
            'Свободны сейчас',
            subtitle: 'Временные сигналы от близких друзей',
          ),
          const SizedBox(height: 12),
        ],
        for (final signal in signals)
          Card(
            child: ListTile(
              minVerticalPadding: 14,
              onTap: () => _showSignal(context, signal),
              leading: CircleAvatar(
                child: Text(
                  signal.emoji ??
                      signalCategoryLabels[signal.category]?.$2 ??
                      '✨',
                ),
              ),
              title: Text(
                signal.authorName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                signal.text ??
                    signalCategoryLabels[signal.category]?.$1 ??
                    signal.category,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        const SizedBox(height: 24),
        const SectionTitle('Остальные друзья'),
        const SizedBox(height: 12),
        for (final friend in friends.where(
          (friend) => !activeIds.contains(friend.id),
        ))
          ListTile(
            leading: CircleAvatar(child: Text(friend.emoji ?? '🙂')),
            title: Text(friend.name),
            subtitle: const Text('место скрыто · без сигнала'),
            enabled: false,
          ),
      ],
    );
  }
}

void _showSignal(
  BuildContext context,
  SignalModel signal,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(signal.emoji ?? '✨', style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(
          '${signal.authorName} · ${signalCategoryLabels[signal.category]?.$1 ?? signal.category}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (signal.text != null) ...[
          const SizedBox(height: 12),
          Text(signal.text!, style: Theme.of(context).textTheme.bodyLarge),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            Chip(label: Text('${signal.participantCount} участник(а)')),
            Chip(label: Text(signal.locationLabel ?? 'место скрыто')),
          ],
        ),
        const SizedBox(height: 18),
        Consumer(
          builder: (context, ref, _) => FilledButton(
            onPressed: () async {
              await ref.read(signalsRepositoryProvider).join(signal.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const SizedBox(
              width: double.infinity,
              child: Center(child: Text('Я с тобой')),
            ),
          ),
        ),
      ],
    ),
  ),
);

class _EmptyCircle extends StatelessWidget {
  const _EmptyCircle();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(36),
    child: Column(
      children: [
        const Text('🪐', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 18),
        Text(
          'Твой круг пока тихий',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Добавь близких друзей или создай первый сигнал.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => context.push('/circles'),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Добавить друзей'),
        ),
      ],
    ),
  );
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        children: [
          for (final offset in const [
            Offset(100, 0),
            Offset(20, 80),
            Offset(180, 100),
            Offset(105, 185),
          ])
            Positioned(
              left: offset.dx,
              top: offset.dy,
              child: const CircleAvatar(
                radius: 34,
                backgroundColor: Colors.white10,
              ),
            ),
          const Positioned(
            left: 105,
            top: 100,
            child: CircleAvatar(radius: 46, backgroundColor: Colors.white24),
          ),
        ],
      ),
    ),
  );
}
