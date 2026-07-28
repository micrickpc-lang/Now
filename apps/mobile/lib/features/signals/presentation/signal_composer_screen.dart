import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../chats/data/chats_repository.dart';
import '../../location_sharing/data/exact_location_share_coordinator.dart';
import '../../location_sharing/data/exact_location_shares_repository.dart';
import '../../location_sharing/domain/exact_location_models.dart';
import '../../map/domain/map_models.dart';
import '../../social/data/social_repository.dart';
import '../data/signals_repository.dart';
import '../domain/signal.dart';
import '../domain/signal_location_payload.dart';

class SignalComposerScreen extends ConsumerStatefulWidget {
  const SignalComposerScreen({this.conversationId, super.key});

  final String? conversationId;
  @override
  ConsumerState<SignalComposerScreen> createState() =>
      _SignalComposerScreenState();
}

class _SignalComposerScreenState extends ConsumerState<SignalComposerScreen> {
  String _category = 'walk';
  MapSelectionResult _location = const MapSelectionResult.none();
  String? _circleId;
  int _duration = 60;
  bool _publishing = false;
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final circles = ref.read(circlesProvider).value ?? const <CircleModel>[];
    final friends = ref.read(friendsProvider).value ?? const <FriendModel>[];
    setState(() => _publishing = true);
    ExactLocationShare? exactShare;
    var signalCreated = false;
    try {
      final selected =
          _circleId ?? (circles.isNotEmpty ? circles.first.id : null);
      var circleIds = selected == null ? <String>[] : <String>[selected];
      var userIds = selected == null
          ? friends.take(20).map((friend) => friend.id).toList()
          : <String>[];
      if (widget.conversationId != null) {
        final conversation = await ref.read(
          conversationProvider(widget.conversationId!).future,
        );
        final currentUserId = await ref.read(currentUserIdProvider.future);
        userIds = conversation.members
            .where((member) => member.userId != currentUserId)
            .map((member) => member.userId)
            .toSet()
            .toList();
        circleIds = <String>[];
        if (userIds.length > 50) {
          throw StateError(
            'Сигнал можно отправить максимум 50 участникам чата.',
          );
        }
      }
      if (circleIds.isEmpty && userIds.isEmpty) {
        throw StateError('Сначала добавь друга или создай круг');
      }
      final exactMode =
          _location.mode == LocationPrivacyMode.exactPin ||
          _location.mode == LocationPrivacyMode.exactLive;
      if (exactMode) {
        final point = _location.sourcePoint;
        if (point == null) {
          throw StateError('Выбери точную точку перед публикацией.');
        }
        final audience = circleIds.length == 1 && userIds.isEmpty
            ? ExactLocationAudience.circle
            : ExactLocationAudience.selectedFriends;
        if (!await _confirmExactShare(
          audience: audience,
          live: _location.mode == LocationPrivacyMode.exactLive,
        )) {
          return;
        }
        exactShare = await ref
            .read(exactLocationShareRepositoryProvider)
            .create(
              point: point,
              audience: audience,
              expiryMode: ExactLocationExpiry.manual,
              explicitConsent: true,
              backgroundUpdatesEnabled: false,
              recipientIds: audience == ExactLocationAudience.selectedFriends
                  ? userIds
                  : const [],
              circleId: audience == ExactLocationAudience.circle
                  ? circleIds.single
                  : null,
              label: _location.label,
            );
      }
      final payload = <String, dynamic>{
        'category': _category,
        'text': _text.text.trim().isEmpty ? null : _text.text.trim(),
        'emoji': signalCategoryLabels[_category]?.$2,
        'startsAt': DateTime.now().toUtc().toIso8601String(),
        'durationMinutes': _duration,
        'format': _category == 'game' || _category == 'movie'
            ? 'ONLINE'
            : 'OFFLINE',
        ...buildSignalLocationPayload(_location),
        if (exactShare != null) 'exactLocationShareId': exactShare.id,
        'maxParticipants': widget.conversationId == null
            ? 4
            : (userIds.length + 1).clamp(2, 20),
        'circleIds': circleIds,
        'userIds': userIds,
      };
      final signal = await ref.read(signalsRepositoryProvider).create(payload);
      signalCreated = true;
      if (_location.mode == LocationPrivacyMode.exactLive &&
          exactShare != null) {
        await ref.read(exactLocationShareCoordinatorProvider).start(exactShare);
      }
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      final roomId = signal['roomId']?.toString();
      if (roomId != null && roomId.isNotEmpty) {
        context.go('/rooms/$roomId');
      } else {
        context.pop(signal);
      }
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
      if (!signalCreated && exactShare != null) {
        try {
          await ref
              .read(exactLocationShareRepositoryProvider)
              .revoke(exactShare.id);
        } catch (_) {
          // Server-side expiry remains the cleanup boundary while offline.
        }
      }
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<bool> _confirmExactShare({
    required ExactLocationAudience audience,
    required bool live,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.share_location_rounded),
        title: Text(
          live
              ? 'Делиться точной геолокацией в реальном времени?'
              : 'Поделиться точной геолокацией?',
        ),
        content: Text(
          '${audience == ExactLocationAudience.circle ? 'Все участники выбранного круга' : 'Выбранные друзья'} увидят эту точку. ${live ? 'Обновления работают, пока приложение открыто.' : 'Точка будет удалена после завершения или отмены сигнала.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    return approved == true;
  }

  @override
  Widget build(BuildContext context) {
    final circles = ref.watch(circlesProvider);
    final exactEnabled = ref.watch(appConfigProvider).canShareExactLocation;
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
          if (widget.conversationId != null)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.forum_outlined),
              title: Text('Участникам этого чата'),
              subtitle: Text(
                'После публикации сигнал появится отдельной карточкой в переписке.',
              ),
            )
          else
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
            groupValue: _location.mode.apiValue,
            onChanged: (value) async {
              final selectedMode = LocationPrivacyMode.values.firstWhere(
                (mode) => mode.apiValue == value,
              );
              if (selectedMode == LocationPrivacyMode.none) {
                setState(() => _location = const MapSelectionResult.none());
                return;
              }
              final exactMode =
                  selectedMode == LocationPrivacyMode.exactPin ||
                  selectedMode == LocationPrivacyMode.exactLive;
              if (exactMode && !exactEnabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Точная геолокация требует защищённого HTTPS-соединения.',
                    ),
                  ),
                );
                return;
              }
              final result = await context.push<MapSelectionResult>(
                '/map',
                extra: exactMode
                    ? const PlacePickerRequest.exactRoom()
                    : PlacePickerRequest.signal(initialMode: selectedMode),
              );
              if (!mounted || result == null) return;
              setState(
                () => _location = exactMode
                    ? MapSelectionResult(
                        mode: selectedMode,
                        sourcePoint: result.sourcePoint,
                        accuracyMeters: result.accuracyMeters,
                        label: result.label,
                      )
                    : result,
              );
            },
            child: Column(
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
                const RadioListTile(
                  value: 'EXACT_PIN',
                  title: Text('Точная точка'),
                  subtitle: Text('Её видят только получатели сигнала'),
                ),
                const RadioListTile(
                  value: 'EXACT_LIVE',
                  title: Text('Точная геолокация онлайн'),
                  subtitle: Text('Обновляется, пока приложение открыто'),
                ),
              ],
            ),
          ),
          if (_location.safeLocation case final safeLocation?)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shield_outlined),
              title: Text(safeLocation.description),
              subtitle: const Text(
                'В сигнал уйдёт только безопасный идентификатор зоны',
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
