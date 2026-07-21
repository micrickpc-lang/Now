import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/onboarding_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/map/presentation/place_picker_screen.dart';
import 'features/memories/presentation/memories_screen.dart';
import 'features/rooms/presentation/room_screen.dart';
import 'features/settings/presentation/settings_screens.dart';
import 'features/signals/presentation/signal_composer_screen.dart';
import 'features/social/presentation/circles_screen.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/signal/new',
        builder: (_, __) => const SignalComposerScreen(),
      ),
      GoRoute(
        path: '/rooms/:id',
        builder: (_, state) => RoomScreen(roomId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/map', builder: (_, __) => const PlacePickerScreen()),
      GoRoute(path: '/circles', builder: (_, __) => const CirclesScreen()),
      GoRoute(path: '/memories', builder: (_, __) => const MemoriesScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/appearance',
        builder: (_, __) => const AppearanceScreen(),
      ),
      GoRoute(path: '/sessions', builder: (_, __) => const SessionsScreen()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: '/blocked', builder: (_, __) => const BlockedUsersScreen()),
      GoRoute(path: '/report', builder: (_, __) => const ReportScreen()),
      GoRoute(
        path: '/delete-account',
        builder: (_, __) => const DeleteAccountScreen(),
      ),
    ],
  ),
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void select(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class SeychasApp extends ConsumerWidget {
  const SeychasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Сейчас',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
