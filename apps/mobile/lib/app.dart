import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/network/realtime_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/onboarding_screen.dart';
import 'features/chats/presentation/chat_screen.dart';
import 'features/chats/presentation/chats_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/map/presentation/place_picker_screen.dart';
import 'features/memories/presentation/memories_screen.dart';
import 'features/navigation/presentation/app_shell.dart';
import 'features/rooms/presentation/room_screen.dart';
import 'features/settings/presentation/settings_screens.dart';
import 'features/signals/presentation/signal_composer_screen.dart';
import 'features/social/presentation/circles_screen.dart';
import 'features/stories/presentation/stories_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _chatsNavigatorKey = GlobalKey<NavigatorState>();
final _nowNavigatorKey = GlobalKey<NavigatorState>();
final _storiesNavigatorKey = GlobalKey<NavigatorState>();
final _profileNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (_, state) {
      final path = state.uri.path;
      final onSplash = path == '/splash';
      final onOnboarding = path == '/onboarding';
      if (session.isLoading) return onSplash ? null : '/splash';
      final authenticated = session.value == true;
      if (!authenticated) return onOnboarding ? null : '/onboarding';
      if (onSplash || onOnboarding) return '/chats';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/chats'),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _chatsNavigatorKey,
            routes: [
              GoRoute(
                path: '/chats',
                builder: (_, __) => const ChatsScreen(),
                routes: [
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: ':id',
                    builder: (_, state) =>
                        ChatScreen(conversationId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _nowNavigatorKey,
            routes: [
              GoRoute(path: '/now', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _storiesNavigatorKey,
            routes: [
              GoRoute(
                path: '/stories',
                builder: (_, __) => const StoriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavigatorKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/signal/new',
        builder: (_, state) => SignalComposerScreen(
          conversationId: state.uri.queryParameters['conversationId'],
        ),
      ),
      GoRoute(
        path: '/rooms/:id',
        builder: (_, state) => RoomScreen(roomId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/map', builder: (_, __) => const PlacePickerScreen()),
      GoRoute(path: '/circles', builder: (_, __) => const CirclesScreen()),
      GoRoute(path: '/memories', builder: (_, __) => const MemoriesScreen()),
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
  );
});

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
    final session = ref.watch(sessionProvider);
    final realtime = ref.watch(realtimeCoordinatorProvider);
    unawaited(
      Future<void>.microtask(
        () => session.value == true ? realtime.start() : realtime.stop(),
      ),
    );
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
