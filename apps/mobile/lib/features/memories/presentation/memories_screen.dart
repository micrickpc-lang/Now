import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../signals/domain/signal.dart';
import '../data/memories_repository.dart';

class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = ref.watch(memoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Воспоминания')),
      body: memories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => FullScreenError(
          message: 'Не удалось загрузить воспоминания',
          onRetry: () => ref.invalidate(memoriesProvider),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyMemories()
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .78,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _MemoryCard(memory: items[index]),
              ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory});
  final MemoryModel memory;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6D5FE8), Color(0xFFFF7B86)],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x446D5FE8),
          blurRadius: 22,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          signalCategoryLabels[memory.category]?.$2 ?? '✨',
          style: const TextStyle(fontSize: 38),
        ),
        const Spacer(),
        Text(
          memory.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${memory.occurredAt.day}.${memory.occurredAt.month}.${memory.occurredAt.year}',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );
}

class _EmptyMemories extends StatelessWidget {
  const _EmptyMemories();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📸', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'Жизнь — не лента',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text(
            'После завершённой активности здесь можно сохранить одну красивую приватную карточку.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}
