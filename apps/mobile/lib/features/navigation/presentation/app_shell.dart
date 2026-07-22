import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../chats/data/chat_controllers.dart';
import '../../chats/data/chats_repository.dart';
import '../../chats/domain/chat_models.dart';
import '../../social/data/social_repository.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = navigationShell.currentIndex < 2
        ? navigationShell.currentIndex
        : navigationShell.currentIndex + 1;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        indicatorColor: AppColors.mint.withValues(alpha: .2),
        onDestinationSelected: (index) {
          if (index == 2) {
            _showCreateMenu(context, ref);
            return;
          }
          final branchIndex = index > 2 ? index - 1 : index;
          navigationShell.goBranch(
            branchIndex,
            initialLocation: branchIndex == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Чаты',
          ),
          NavigationDestination(
            icon: Icon(Icons.radio_button_unchecked_rounded),
            selectedIcon: Icon(Icons.adjust_rounded),
            label: 'Сейчас',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Создать',
          ),
          NavigationDestination(
            icon: Icon(Icons.timelapse_rounded),
            selectedIcon: Icon(Icons.donut_large_rounded),
            label: 'Истории',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateMenu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_CreateAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const _CreateMenu(),
    );
    if (!context.mounted || action == null) return;
    if (action == _CreateAction.signal) {
      context.push('/signal/new');
      return;
    }
    if (action == _CreateAction.chat) {
      await _createDirect(context, ref);
      return;
    }
    if (action == _CreateAction.group) {
      await _createGroup(context, ref);
      return;
    }
    final label = switch (action) {
      _CreateAction.chat || _CreateAction.group => '',
      _CreateAction.story => 'Истории',
      _CreateAction.call => 'Звонки',
      _CreateAction.signal => '',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label появится в следующем этапе.')),
    );
  }

  Future<void> _createDirect(BuildContext context, WidgetRef ref) async {
    try {
      final friends = await ref.read(friendsProvider.future);
      if (!context.mounted) return;
      final friend = await showDialog<FriendModel>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Новый чат'),
          children: [
            if (friends.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Сначала добавь взаимного друга.'),
              ),
            for (final friend in friends)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, friend),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(friend.emoji ?? '🙂')),
                  title: Text(friend.name),
                  subtitle: const Text('Взаимный друг'),
                ),
              ),
          ],
        ),
      );
      if (friend == null || !context.mounted) return;
      final conversation = await ref
          .read(chatsRepositoryProvider)
          .createDirect(
            friendId: friend.id,
            displayName: friend.name,
            emoji: friend.emoji,
          );
      ref.invalidate(chatsProvider);
      if (context.mounted) context.push('/chats/${conversation.id}');
    } catch (error) {
      if (context.mounted) _showCreateError(context, error);
    }
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    try {
      final friends = await ref.read(friendsProvider.future);
      if (!context.mounted) return;
      final draft = await showDialog<_GroupDraft>(
        context: context,
        builder: (_) => _GroupCreatorDialog(friends: friends),
      );
      if (draft == null || !context.mounted) return;
      final byId = {for (final friend in friends) friend.id: friend};
      final conversation = await ref
          .read(chatsRepositoryProvider)
          .createGroup(
            title: draft.title,
            members: [
              for (final id in draft.memberIds)
                ConversationMember(
                  userId: id,
                  role: ConversationRole.member,
                  displayName: byId[id]?.name ?? 'Друг',
                  emoji: byId[id]?.emoji,
                ),
            ],
          );
      ref.invalidate(chatsProvider);
      if (context.mounted) context.push('/chats/${conversation.id}');
    } catch (error) {
      if (context.mounted) _showCreateError(context, error);
    }
  }

  void _showCreateError(BuildContext context, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Не удалось создать чат: $error')));
  }
}

enum _CreateAction { signal, chat, group, story, call }

class _CreateMenu extends StatelessWidget {
  const _CreateMenu();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Text(
            'Создать',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        _CreateTile(
          icon: Icons.bolt_rounded,
          title: 'Новый сигнал',
          subtitle: 'Договориться о встрече прямо сейчас',
          action: _CreateAction.signal,
        ),
        _CreateTile(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Новый чат',
          subtitle: 'Выбрать взаимного друга',
          action: _CreateAction.chat,
        ),
        _CreateTile(
          icon: Icons.group_outlined,
          title: 'Новая группа',
          subtitle: 'Название и близкие друзья',
          action: _CreateAction.group,
        ),
        _CreateTile(
          icon: Icons.timelapse_rounded,
          title: 'Новая история',
          subtitle: 'Следующая продуктовая фаза',
          action: _CreateAction.story,
        ),
        _CreateTile(
          icon: Icons.call_outlined,
          title: 'Новый звонок',
          subtitle: 'После безопасной WebRTC-интеграции',
          action: _CreateAction.call,
        ),
      ],
    ),
  );
}

class _GroupDraft {
  const _GroupDraft({required this.title, required this.memberIds});
  final String title;
  final Set<String> memberIds;
}

class _GroupCreatorDialog extends StatefulWidget {
  const _GroupCreatorDialog({required this.friends});
  final List<FriendModel> friends;

  @override
  State<_GroupCreatorDialog> createState() => _GroupCreatorDialogState();
}

class _GroupCreatorDialogState extends State<_GroupCreatorDialog> {
  final _title = TextEditingController();
  final Set<String> _selected = {};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новая группа'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.friends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Для группы нужен хотя бы один взаимный друг.'),
              ),
            for (final friend in widget.friends)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(friend.id),
                secondary: CircleAvatar(child: Text(friend.emoji ?? '🙂')),
                title: Text(friend.name),
                onChanged: (selected) => setState(() {
                  if (selected == true) {
                    _selected.add(friend.id);
                  } else {
                    _selected.remove(friend.id);
                  }
                }),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _title.text.trim().length < 2 || _selected.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _GroupDraft(
                  title: _title.text.trim(),
                  memberIds: Set.unmodifiable(_selected),
                ),
              ),
        child: const Text('Создать'),
      ),
    ],
  );
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _CreateAction action;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    onTap: () => Navigator.pop(context, action),
  );
}
