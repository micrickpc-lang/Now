import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../social/data/social_repository.dart';
import '../data/signals_repository.dart';
import '../domain/signal.dart';

class SignalComposerScreen extends ConsumerStatefulWidget {
  const SignalComposerScreen({super.key});
  @override
  ConsumerState<SignalComposerScreen> createState() =>
      _SignalComposerScreenState();
}

class _SignalComposerScreenState extends ConsumerState<SignalComposerScreen> {
  String _category = 'walk';
  String _location = 'NONE';
  String? _circleId;
  int _duration = 60;
  bool _publishing = false;
  double? _latitude;
  double? _longitude;
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final circles = ref.read(circlesProvider).value ?? const <CircleModel>[];
    final friends = ref.read(friendsProvider).value ?? const <FriendModel>[];
    final selected =
        _circleId ?? (circles.isNotEmpty ? circles.first.id : null);
    if (selected == null && friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавь друга или создай круг')),
      );
      return;
    }
    setState(() => _publishing = true);
    try {
      final payload = <String, dynamic>{
        'category': _category,
        'text': _text.text.trim().isEmpty ? null : _text.text.trim(),
        'emoji': signalCategoryLabels[_category]?.$2,
        'startsAt': DateTime.now().toUtc().toIso8601String(),
        'durationMinutes': _duration,
        'format': _category == 'game' || _category == 'movie'
            ? 'ONLINE'
            : 'OFFLINE',
        'locationMode': _location,
        'maxParticipants': 4,
        'circleIds': selected == null ? <String>[] : [selected],
        'userIds': selected == null
            ? friends.take(20).map((friend) => friend.id).toList()
            : <String>[],
      };
      if (_location == 'APPROXIMATE') {
        if (_latitude == null || _longitude == null) {
          throw StateError('Выбери приблизительную зону на карте');
        }
        payload['latitude'] = _latitude;
        payload['longitude'] = _longitude;
      }
      await ref.read(signalsRepositoryProvider).create(payload);
      await HapticFeedback.mediumImpact();
      if (mounted) context.pop(true);
    } on DioException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.response?.data.toString() ?? 'Не удалось опубликовать',
            ),
          ),
        );
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final circles = ref.watch(circlesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый сигнал'),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: const Text('Готово'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Чего хочется?',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.7,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final entry in signalCategoryLabels.entries)
                _CategoryCard(
                  label: entry.value.$1,
                  emoji: entry.value.$2,
                  selected: _category == entry.key,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _category = entry.key);
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _text,
            maxLength: 180,
            decoration: const InputDecoration(
              labelText: 'Пара слов · необязательно',
              hintText: 'Кто на вечернюю прогулку?',
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Сколько времени?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30 мин')),
              ButtonSegment(value: 60, label: Text('1 час')),
              ButtonSegment(value: 120, label: Text('2 часа')),
            ],
            selected: {_duration},
            onSelectionChanged: (value) =>
                setState(() => _duration = value.first),
          ),
          const SizedBox(height: 22),
          Text('Кому показать?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          circles.when(
            data: (items) => DropdownButtonFormField<String>(
              initialValue:
                  _circleId ?? (items.isNotEmpty ? items.first.id : null),
              decoration: const InputDecoration(labelText: 'Закрытый круг'),
              items: items
                  .map(
                    (circle) => DropdownMenuItem(
                      value: circle.id,
                      child: Text(
                        '${circle.emoji ?? '✨'} ${circle.name} · ${circle.memberCount}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _circleId = value),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) =>
                const Text('Круги недоступны — выберем друзей напрямую'),
          ),
          const SizedBox(height: 22),
          Text('Место', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          RadioGroup<String>(
            groupValue: _location,
            onChanged: (value) async {
              if (value == 'APPROXIMATE') {
                final point = await context.push<Map<String, double>>('/map');
                if (!mounted || point == null) return;
                setState(() {
                  _location = value!;
                  _latitude = point['latitude'];
                  _longitude = point['longitude'];
                });
              } else {
                setState(() {
                  _location = value!;
                  _latitude = null;
                  _longitude = null;
                });
              }
            },
            child: const Column(
              children: [
                RadioListTile(
                  value: 'NONE',
                  title: Text('Без местоположения'),
                  subtitle: Text('Выбрано по умолчанию'),
                ),
                RadioListTile(value: 'CITY', title: Text('Только город')),
                RadioListTile(value: 'DISTRICT', title: Text('Только район')),
                RadioListTile(
                  value: 'APPROXIMATE',
                  title: Text('Приблизительная зона'),
                  subtitle: Text('Точность намеренно снижена'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: _publishing ? null : _publish,
            icon: _publishing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bolt_rounded),
            label: const Text('Опубликовать сейчас'),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });
  final String label, emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: AnimatedContainer(
        duration: AppDuration.quick,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.md),
          color: selected
              ? AppColors.violet.withValues(alpha: .25)
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: selected
                ? AppColors.violet
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 27)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
