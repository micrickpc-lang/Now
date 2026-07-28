import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
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
    Future<void>.delayed(const Duration(milliseconds: 450), () async {
      final active = await ref.read(sessionProvider.future);
      final profileComplete = active
          ? await ref.read(authRepositoryProvider).profileComplete()
          : false;
      if (!mounted) return;
      context.go(
        active
            ? profileComplete
                  ? '/app/chats'
                  : '/auth/profile-setup'
            : '/auth',
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 42, color: AppColors.violet),
          SizedBox(height: 12),
          Text(
            'Seychas',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ],
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
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode({bool resend = false}) async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (resend) {
        await auth.resendEmailCode(email);
      } else {
        await auth.requestEmailCode(email);
      }
      if (mounted) setState(() => _codeSent = true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEmail() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the six-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profileComplete = await ref
          .read(authRepositoryProvider)
          .verifyEmailCode(email: _email.text.trim(), code: _code.text.trim());
      await ref.read(sessionProvider.notifier).signedIn();
      if (mounted)
        context.go(profileComplete ? '/app/chats' : '/auth/profile-setup');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profileComplete = await ref
          .read(authRepositoryProvider)
          .signInWithGoogle();
      await ref.read(sessionProvider.notifier).signedIn();
      if (mounted)
        context.go(profileComplete ? '/app/chats' : '/auth/profile-setup');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    if (error is DioException) {
      final data = error.response?.data;
      setState(
        () => _error = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Unable to continue. Check your connection and try again.',
      );
      return;
    }
    setState(() => _error = 'Unable to continue. Please try again.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 42,
                  color: AppColors.violet,
                ),
                const SizedBox(height: 20),
                Text(
                  _codeSent ? 'Check your email' : 'Sign in to Seychas',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? 'Enter the six-digit code sent to ${_email.text.trim()}.'
                      : 'Use your email or Google account to continue.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                if (!_codeSent) ...[
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _sendCode(),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _sendCode,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue with email'),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Icon(Icons.account_circle_outlined),
                    label: const Text('Continue with Google'),
                  ),
                ] else ...[
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                    onSubmitted: (_) => _verifyEmail(),
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _verifyEmail,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify and continue'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _sendCode(resend: true),
                    child: const Text('Resend code'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _codeSent = false),
                    child: const Text('Use a different email'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();
    if (name.length < 2 || !RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(username)) {
      setState(
        () => _error = 'Enter a name and a username using a-z, 0-9, or _.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .completeProfile(displayName: name, username: username);
      if (mounted) context.go('/app/chats');
    } catch (error) {
      _showProfileSaveError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showProfileSaveError(Object error) {
    if (!mounted) return;
    if (error is TimeoutException ||
        (error is DioException &&
            (error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.sendTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.connectionError))) {
      setState(
        () => _error =
            'Cannot reach the server. Check the API address and try again.',
      );
      return;
    }
    if (error is DioException) {
      final data = error.response?.data;
      setState(
        () => _error = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Unable to save the profile. Please try again.',
      );
      return;
    }
    setState(() => _error = 'Unable to save the profile. Please try again.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Finish your profile')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'How should friends see you?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _username,
                  maxLength: 32,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const Spacer(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _complete,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Complete profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
