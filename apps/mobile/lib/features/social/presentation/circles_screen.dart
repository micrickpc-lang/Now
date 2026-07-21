import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/widgets/app_widgets.dart';
import '../data/social_repository.dart';

class CirclesScreen extends ConsumerWidget {
  const CirclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(circlesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Близкие круги'),
        actions: [
          IconButton(
            onPressed: () => _showInvite(context, ref),
            tooltip: 'Пригласить друга',
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCircle(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Новый круг'),
      ),
      body: circles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => FullScreenError(
          message: 'Не удалось загрузить круги',
          onRetry: () => ref.invalidate(circlesProvider),
        ),
        data: (items) => items.isEmpty
            ? _empty(context, ref)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SectionTitle(
                    'Только свои',
                    subtitle: 'Сигналы внутри закрытых кругов',
                  ),
                  const SizedBox(height: 16),
                  for (final circle in items)
                    Card(
                      child: ListTile(
                        minVerticalPadding: 16,
                        leading: CircleAvatar(child: Text(circle.emoji ?? '✨')),
                        title: Text(
                          circle.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('${circle.memberCount} участник(а)'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _empty(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🫶', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'Собери свой первый круг',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Например: «Школа», «Двор» или «Самые близкие». Все круги закрытые.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _showInvite(context, ref),
            icon: const Icon(Icons.link),
            label: const Text('Пригласить друга'),
          ),
        ],
      ),
    ),
  );

  Future<void> _showInvite(BuildContext context, WidgetRef ref) async {
    showDialog<void>(
      context: context,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final invite = await ref.read(socialRepositoryProvider).invite();
      if (!context.mounted) return;
      Navigator.pop(context);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Приглашение на 24 часа',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Ссылка одноразовая. После принятия вы станете взаимными друзьями.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(14),
                child: QrImageView(
                  data: invite['deepLink'] as String,
                  size: 190,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                invite['shortCode'] as String,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Покажи QR или отправь короткий код'),
            ],
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать приглашение')),
        );
      }
    }
  }

  Future<void> _createCircle(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final friends = await ref.read(friendsProvider.future);
    if (!context.mounted) return;
    final selected = <String>{};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Новый закрытый круг'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  for (final friend in friends)
                    CheckboxListTile(
                      value: selected.contains(friend.id),
                      onChanged: (value) => setLocal(
                        () => value == true
                            ? selected.add(friend.id)
                            : selected.remove(friend.id),
                      ),
                      title: Text(friend.name),
                      secondary: CircleAvatar(
                        child: Text(friend.emoji ?? '🙂'),
                      ),
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
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                await ref
                    .read(socialRepositoryProvider)
                    .createCircle(name.text.trim(), selected.toList());
                ref.invalidate(circlesProvider);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
  }
}
