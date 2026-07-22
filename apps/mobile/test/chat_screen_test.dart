import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/config/app_config.dart';
import 'package:seychas/core/storage/local_cache.dart';
import 'package:seychas/core/theme/app_theme.dart';
import 'package:seychas/features/chats/presentation/chat_screen.dart';

void main() {
  testWidgets('demo chat renders composer, history and signal card', (
    tester,
  ) async {
    final cache = LocalCache.forTest(NativeDatabase.memory());
    addTearDown(cache.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseAppConfigProvider.overrideWithValue(
            const AppConfig(
              environment: AppEnvironment.development,
              apiBaseUrl: 'http://demo.invalid/api/v1',
              wsBaseUrl: 'http://demo.invalid',
              firstPartyDomains: {},
              demoMode: true,
            ),
          ),
          initialDemoModeProvider.overrideWithValue(true),
          localCacheProvider.overrideWithValue(cache),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ChatScreen(conversationId: 'demo-direct-anya'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Аня'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-signal')), findsOneWidget);
    expect(find.text('Сигнал для участников чата'), findsOneWidget);
  });
}
