import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Профиль')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _me(ref),
      builder: (context, snapshot) {
        final profile = snapshot.data?['profile'] as Map<String, dynamic>?;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.violet, AppColors.coral],
                      ),
                    ),
                    child: Text(
                      profile?['emoji']?.toString() ?? 'Я',
                      style: const TextStyle(
                        fontSize: 38,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile?['displayName']?.toString() ?? 'Твой профиль',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(
                    'виден только взаимным друзьям',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _Tile(
              icon: Icons.groups_2_outlined,
              title: 'Круги',
              onTap: () => context.push('/circles'),
            ),
            _Tile(
              icon: Icons.auto_awesome_motion_outlined,
              title: 'Воспоминания',
              onTap: () => context.push('/memories'),
            ),
            _Tile(
              icon: Icons.palette_outlined,
              title: 'Оформление',
              onTap: () => context.push('/appearance'),
            ),
            _Tile(
              icon: Icons.devices_outlined,
              title: 'Активные сессии',
              onTap: () => context.push('/sessions'),
            ),
            _Tile(
              icon: Icons.shield_outlined,
              title: 'Настройки приватности',
              onTap: () => context.push('/privacy'),
            ),
            _Tile(
              icon: Icons.block_outlined,
              title: 'Заблокированные',
              onTap: () => context.push('/blocked'),
            ),
            _Tile(
              icon: Icons.flag_outlined,
              title: 'Пожаловаться',
              onTap: () => context.push('/report'),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(sessionProvider.notifier).logout();
                if (context.mounted) context.go('/onboarding');
              },
              icon: const Icon(Icons.logout),
              label: const Text('Выйти на этом устройстве'),
            ),
            TextButton(
              onPressed: () => context.push('/delete-account'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Удалить аккаунт и данные'),
            ),
          ],
        );
      },
    ),
  );
  Future<Map<String, dynamic>> _me(WidgetRef ref) async =>
      (await ref
              .read(apiClientProvider)
              .dio
              .get<Map<String, dynamic>>('/users/me'))
          .data!;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      minVerticalPadding: 10,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Оформление')),
      body: RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (value) =>
            ref.read(themeModeProvider.notifier).select(value!),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            RadioListTile(
              value: ThemeMode.system,
              title: Text('Как на устройстве'),
              secondary: Icon(Icons.brightness_auto_outlined),
            ),
            RadioListTile(
              value: ThemeMode.light,
              title: Text('Светлое'),
              secondary: Icon(Icons.light_mode_outlined),
            ),
            RadioListTile(
              value: ThemeMode.dark,
              title: Text('Тёмное'),
              secondary: Icon(Icons.dark_mode_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Активные сессии')),
    body: FutureBuilder<List<dynamic>>(
      future: _load(ref),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'Если устройство незнакомо, отзови его и смени доступ к номеру телефона.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
            for (final raw in snapshot.data!)
              Card(
                child: ListTile(
                  leading: Icon(
                    (raw['device']?['platform']) == 'ios'
                        ? Icons.phone_iphone
                        : Icons.phone_android,
                  ),
                  title: Text(
                    raw['device']?['label']?.toString() ??
                        'Мобильное устройство',
                  ),
                  subtitle: Text('Активность: ${raw['lastUsedAt']}'),
                  trailing: IconButton(
                    onPressed: () async {
                      await ref
                          .read(apiClientProvider)
                          .dio
                          .delete<void>('/auth/sessions/${raw['id']}');
                      if (context.mounted) context.pop();
                    },
                    tooltip: 'Отозвать сессию',
                    icon: const Icon(Icons.logout),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  Future<List<dynamic>> _load(WidgetRef ref) async =>
      (await ref
              .read(apiClientProvider)
              .dio
              .get<List<dynamic>>('/auth/sessions'))
          .data!;
}

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});
  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _recent = false;
  bool _quiet = true;
  bool _saving = false;
  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(apiClientProvider)
        .dio
        .patch<void>(
          '/users/me/privacy',
          data: {
            'showRecentActivity': _recent,
            'settings': {
              'exactLocationDefault': false,
              'quietHours': _quiet,
              'backgroundLocation': false,
            },
          },
        );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Приватность')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.mint.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_rounded, color: AppColors.mint),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Точное место всегда выключено по умолчанию и доступно только в активной комнате после отдельного подтверждения.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          value: _recent,
          onChanged: (value) => setState(() => _recent = value),
          title: const Text('Показывать недавнюю активность'),
          subtitle: const Text('Без точного времени'),
        ),
        SwitchListTile(
          value: _quiet,
          onChanged: (value) => setState(() => _quiet = value),
          title: const Text('Тихие часы'),
          subtitle: const Text('Не присылать необязательные уведомления ночью'),
        ),
        const ListTile(
          leading: Icon(Icons.location_off),
          title: Text('Фоновая геолокация'),
          subtitle: Text('Всегда выключена'),
          trailing: Icon(Icons.lock_outline),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Заблокированные')),
    body: FutureBuilder<List<dynamic>>(
      future: _load(ref),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty)
          return const Center(child: Text('Здесь пока никого нет'));
        return ListView(
          children: [
            for (final row in snapshot.data!)
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_off_outlined),
                ),
                title: Text(row['displayName']?.toString() ?? 'Пользователь'),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(apiClientProvider)
                        .dio
                        .delete<void>('/users/${row['id']}/block');
                    if (context.mounted) context.pop();
                  },
                  child: const Text('Разблокировать'),
                ),
              ),
          ],
        );
      },
    ),
  );
  Future<List<dynamic>> _load(WidgetRef ref) async =>
      (await ref
              .read(apiClientProvider)
              .dio
              .get<List<dynamic>>('/users/me/blocks'))
          .data!;
}

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  String _category = 'spam';
  final _details = TextEditingController();
  final _userId = TextEditingController();
  bool _sending = false;
  @override
  void dispose() {
    _details.dispose();
    _userId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Пожаловаться')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Если есть непосредственная опасность, обратись в экстренные службы. Жалоба попадёт только команде Trust & Safety.',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Причина'),
          items:
              const {
                    'spam': 'Спам',
                    'fraud': 'Мошенничество',
                    'threats': 'Угрозы',
                    'harassment': 'Домогательства',
                    'doxxing': 'Публикация личных данных',
                    'unsafe_meeting': 'Опасная встреча',
                    'content': 'Нежелательный контент',
                    'impersonation': 'Выдача себя за другого',
                    'other': 'Другое',
                  }.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
          onChanged: (value) => setState(() => _category = value!),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _userId,
          decoration: const InputDecoration(labelText: 'ID пользователя'),
          maxLength: 36,
        ),
        TextField(
          controller: _details,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Что произошло?'),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _sending
              ? null
              : () async {
                  setState(() => _sending = true);
                  await ref
                      .read(apiClientProvider)
                      .dio
                      .post<void>(
                        '/reports',
                        data: {
                          'reportedUserId': _userId.text.trim(),
                          'category': _category,
                          'details': _details.text.trim(),
                        },
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Жалоба отправлена')),
                    );
                    context.pop();
                  }
                },
          child: const Text('Отправить жалобу'),
        ),
      ],
    ),
  );
}

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmation = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Удаление аккаунта')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Icon(
          Icons.delete_forever_outlined,
          size: 58,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 20),
        Text(
          'Это действие необратимо',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Будут отозваны сессии и геолокация, удалены push-токены, профиль и медиа, сообщения анонимизированы по политике хранения. Ты исчезнешь из кругов.',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _confirmation,
          decoration: const InputDecoration(labelText: 'Введи УДАЛИТЬ'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await ref
                        .read(apiClientProvider)
                        .dio
                        .delete<void>(
                          '/users/me',
                          data: {'confirmation': _confirmation.text.trim()},
                        );
                    await ref.read(sessionProvider.notifier).logout();
                    if (context.mounted) context.go('/onboarding');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Удалить аккаунт и данные'),
        ),
      ],
    ),
  );
}
