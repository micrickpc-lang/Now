import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/auth_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      final active = await ref.read(sessionProvider.future);
      if (mounted) context.go(active ? '/' : '/onboarding');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.3, -.4),
          radius: 1.2,
          colors: [Color(0xFF3A326F), AppColors.ink],
        ),
      ),
      child: Center(
        child: Semantics(
          label: 'Сейчас',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    colors: [AppColors.violet, AppColors.coral],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x668B7CFF),
                      blurRadius: 38,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: const Text(
                  'С',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Сейчас',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _name = TextEditingController();
  int _step = 0;
  bool _busy = false;
  String? _error;
  DateTime? _birthDate;

  @override
  void dispose() {
    _page.dispose();
    _phone.dispose();
    _otp.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_step == 0) {
        if (_phone.text.trim().length < 10)
          throw const FormatException('Введите номер телефона');
        await ref.read(authRepositoryProvider).requestOtp(_phone.text.trim());
      }
      if (_step == 2 && _birthDate == null)
        throw const FormatException('Выберите дату рождения');
      if (_step == 3 && _name.text.trim().length < 2)
        throw const FormatException('Введите имя');
      if (_step == 5) {
        if (_otp.text.length != 6)
          throw const FormatException('Введите шестизначный код');
        await ref
            .read(authRepositoryProvider)
            .verify(
              phone: _phone.text.trim(),
              code: _otp.text,
              birthDate: _birthDate!,
              displayName: _name.text.trim(),
            );
        await ref.read(sessionProvider.notifier).signedIn();
        if (mounted) context.go('/');
        return;
      }
      _step += 1;
      if (_step == 5 && ref.read(appConfigProvider).demoMode) {
        _otp.text = '123456';
      }
      await _page.animateToPage(
        _step,
        duration: AppDuration.normal,
        curve: Curves.easeOutCubic,
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      setState(
        () => _error = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Не удалось связаться с сервером',
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Row(
              children: [
                if (_step > 0)
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _step -= 1;
                            _page.animateToPage(
                              _step,
                              duration: AppDuration.normal,
                              curve: Curves.easeOut,
                            );
                            setState(() {});
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Назад',
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: LinearProgressIndicator(
                    value: (_step + 1) / 6,
                    borderRadius: BorderRadius.circular(20),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step(
                    icon: Icons.waving_hand_rounded,
                    title: 'Ближе — прямо сейчас',
                    text:
                        'Только друзья, которых ты знаешь. Без публичной ленты и случайных людей.',
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: 'Номер телефона',
                        hintText: '+7 900 000-00-00',
                      ),
                    ),
                  ),
                  const _Step(
                    icon: Icons.lock_outline_rounded,
                    title: 'Твоё пространство закрыто',
                    text:
                        'Сигналы видят только взаимные друзья и выбранные закрытые круги. Номер никому не показываем.',
                    child: _PrivacyBullets(),
                  ),
                  _Step(
                    icon: Icons.cake_outlined,
                    title: 'Сколько тебе лет?',
                    text:
                        'Минимальный возраст — 14 лет. Для пользователей младше 18 включается усиленный режим приватности.',
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showDatePicker(
                          context: context,
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now().subtract(
                            const Duration(days: 14 * 365),
                          ),
                          initialDate: DateTime(2006),
                        );
                        if (value != null) setState(() => _birthDate = value);
                      },
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(
                        _birthDate == null
                            ? 'Выбрать дату рождения'
                            : '${_birthDate!.day}.${_birthDate!.month}.${_birthDate!.year}',
                      ),
                    ),
                  ),
                  _Step(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Как тебя зовут?',
                    text:
                        'Имя увидят только твои друзья. Публичного профиля здесь нет.',
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      decoration: const InputDecoration(labelText: 'Имя'),
                    ),
                  ),
                  const _Step(
                    icon: Icons.tune_rounded,
                    title: 'Разрешения — по делу',
                    text:
                        'Контакты нужны только для поиска уже знакомых людей и остаются необязательными. Геолокацию запросим один раз при выборе места — фонового доступа нет.',
                    child: _PermissionCards(),
                  ),
                  _Step(
                    icon: Icons.sms_outlined,
                    title: 'Последний шаг',
                    text:
                        'Введи код из SMS. В development используется код из локальной конфигурации.',
                    child: TextField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        letterSpacing: 12,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(labelText: 'Код'),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : _next,
              child: SizedBox(
                width: double.infinity,
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_step == 5 ? 'Войти в свой круг' : 'Продолжить'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.text,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String text;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [AppColors.violet, AppColors.coral],
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 14),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          child,
        ],
      ),
    ),
  );
}

class _PrivacyBullets extends StatelessWidget {
  const _PrivacyBullets();
  @override
  Widget build(BuildContext context) => const GlassPanel(
    child: Column(
      children: [
        ListTile(
          leading: Icon(Icons.location_off_rounded),
          title: Text('Без фоновой геолокации'),
        ),
        ListTile(
          leading: Icon(Icons.group_outlined),
          title: Text('Только взаимные друзья'),
        ),
        ListTile(
          leading: Icon(Icons.timer_outlined),
          title: Text('Сигналы исчезают по сроку'),
        ),
      ],
    ),
  );
}

class _PermissionCards extends StatelessWidget {
  const _PermissionCards();
  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Card(
        child: ListTile(
          minVerticalPadding: 16,
          leading: Icon(Icons.contacts_outlined),
          title: Text('Контакты'),
          subtitle: Text('Необязательно · приложение работает без них'),
          trailing: Icon(Icons.chevron_right),
        ),
      ),
      Card(
        child: ListTile(
          minVerticalPadding: 16,
          leading: Icon(Icons.near_me_outlined),
          title: Text('Местоположение'),
          subtitle: Text('Только при явном выборе места'),
          trailing: Icon(Icons.chevron_right),
        ),
      ),
    ],
  );
}
