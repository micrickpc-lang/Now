import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/auth_repository.dart';

const _countryCallingCodes = [
  _CountryCallingCode('Россия', '+7'),
  _CountryCallingCode('США', '+1'),
  _CountryCallingCode('Великобритания', '+44'),
  _CountryCallingCode('Германия', '+49'),
];

class _CountryCallingCode {
  const _CountryCallingCode(this.country, this.code);

  final String country;
  final String code;
}

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
      if (mounted) context.go(active ? '/chats' : '/onboarding');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.ink),
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
                  color: AppColors.violet,
                  border: Border.all(color: AppColors.mint, width: 2),
                ),
                child: const Text(
                  'now',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
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
  String _countryCode = '+7';
  int _step = 0;
  bool _busy = false;
  String? _error;
  DateTime? _birthDate;
  Timer? _resendTimer;
  int _retryAfterSeconds = 0;

  @override
  void dispose() {
    _page.dispose();
    _phone.dispose();
    _otp.dispose();
    _name.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _retryAfterSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryAfterSeconds <= 1) {
        timer.cancel();
        setState(() => _retryAfterSeconds = 0);
      } else {
        setState(() => _retryAfterSeconds -= 1);
      }
    });
  }

  void _showNetworkError(DioException error) {
    final data = error.response?.data;
    setState(
      () => _error = data is Map && data['message'] != null
          ? data['message'].toString()
          : 'Не удалось связаться с сервером',
    );
  }

  Future<void> _resendOtp() async {
    if (_busy || _retryAfterSeconds > 0) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final retryAfter = await ref
          .read(authRepositoryProvider)
          .resendOtp(_normalizedPhone());
      _startResendCountdown(retryAfter);
    } on DioException catch (error) {
      _showNetworkError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _maskedPhone {
    final digits = _normalizedPhone().replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return 'указанный номер';
    return 'номер ••${digits.substring(digits.length - 2)}';
  }

  String _normalizedPhone() {
    final raw = _phone.text.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (raw.startsWith('+')) return raw;
    return '$_countryCode${raw.replaceAll(RegExp(r'\D'), '')}';
  }

  bool get _hasValidPhone =>
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(_normalizedPhone());

  Future<void> _next() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_step == 0) {
        if (!_hasValidPhone) {
          throw const FormatException('Введите номер в международном формате');
        }
        final retryAfter = await ref
            .read(authRepositoryProvider)
            .requestOtp(_normalizedPhone());
        _startResendCountdown(retryAfter);
      }
      if (_step == 1 && !RegExp(r'^\d{6}$').hasMatch(_otp.text.trim()))
        throw const FormatException('Введите шестизначный код');
      if (_step == 3 && _birthDate == null)
        throw const FormatException('Выберите дату рождения');
      if (_step == 4 && _name.text.trim().length < 2)
        throw const FormatException('Введите имя');
      if (_step == 5) {
        await ref
            .read(authRepositoryProvider)
            .verify(
              phone: _normalizedPhone(),
              code: _otp.text.trim(),
              birthDate: _birthDate!,
              displayName: _name.text.trim(),
            );
        await ref.read(sessionProvider.notifier).signedIn();
        if (mounted) context.go('/chats');
        return;
      }
      _step += 1;
      if (_step == 1 && ref.read(appConfigProvider).demoMode) {
        _otp.text = '123456';
      }
      await _page.animateToPage(
        _step,
        duration: AppDuration.normal,
        curve: Curves.easeOutCubic,
      );
    } on DioException catch (error) {
      _showNetworkError(error);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    return Scaffold(
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
                      title: 'Твой номер телефона',
                      text:
                          'Нужен для входа и восстановления аккаунта. Номер увидишь только ты.',
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 132,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _countryCode,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Код',
                                  ),
                                  items: _countryCallingCodes
                                      .map(
                                        (entry) => DropdownMenuItem(
                                          value: entry.code,
                                          child: Text('${entry.code} ${entry.country}'),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _busy
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() => _countryCode = value);
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('phone-input'),
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Номер телефона',
                                    hintText: '900 000-00-00',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (config.environment !=
                              AppEnvironment.production) ...[
                            const SizedBox(height: 12),
                            if (config.demoMode)
                              Column(
                                children: [
                                  const ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.offline_bolt_rounded,
                                      color: AppColors.mint,
                                    ),
                                    title: Text('Демо работает без сервера'),
                                    subtitle: Text(
                                      'Режим и история чатов сохранятся после перезапуска',
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () async {
                                      await ref
                                          .read(demoModeProvider.notifier)
                                          .setEnabled(false);
                                      _phone.clear();
                                    },
                                    icon: const Icon(Icons.cloud_outlined),
                                    label: const Text(
                                      'Перейти к обычному входу',
                                    ),
                                  ),
                                ],
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await ref
                                      .read(demoModeProvider.notifier)
                                      .setEnabled(true);
                                  _phone.text = '999 000-00-00';
                                },
                                icon: const Icon(Icons.offline_bolt_outlined),
                                label: const Text(
                                  'Использовать демо без сервера',
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    _Step(
                      icon: Icons.sms_outlined,
                      title: 'Код из сообщения',
                      text:
                          'Отправили на $_maskedPhone. Введи шесть цифр из SMS.',
                      child: Column(
                        children: [
                          _OtpCodeInput(
                            controller: _otp,
                            onChanged: () => setState(() {}),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextButton.icon(
                            onPressed: _busy || _retryAfterSeconds > 0
                                ? null
                                : _resendOtp,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(
                              _retryAfterSeconds > 0
                                  ? 'Повторно через $_retryAfterSeconds с'
                                  : 'Отправить код ещё раз',
                            ),
                          ),
                        ],
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
                        : Text(
                            _step == 0
                                ? 'Получить код'
                                : _step == 5
                                ? 'Войти в свой круг'
                                : 'Продолжить',
                          ),
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

class _OtpCodeInput extends StatefulWidget {
  const _OtpCodeInput({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<_OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<_OtpCodeInput> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      label: 'Код из SMS, шесть цифр',
      textField: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusNode.requestFocus,
        child: SizedBox(
          height: 58,
          child: Stack(
            children: [
              Row(
                children: List.generate(6, (index) {
                  final hasValue = index < code.length;
                  final active = _focusNode.hasFocus && index == code.length;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(
                          color: active ? AppColors.violet : borderColor,
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        hasValue ? code[index] : '',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  );
                }),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: .01,
                  child: TextField(
                    key: const ValueKey('otp-code-input'),
                    controller: widget.controller,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    maxLength: 6,
                    onChanged: (_) => widget.onChanged(),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(color: Colors.transparent),
                    cursorColor: Colors.transparent,
                    showCursor: false,
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
