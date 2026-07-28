import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/config/app_config.dart';
import 'package:seychas/core/theme/app_theme.dart';
import 'package:seychas/features/auth/presentation/onboarding_screen.dart';

void main() {
  testWidgets('onboarding starts with a phone input', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const OnboardingScreen(),
        ),
      ),
    );
    expect(find.text('Твой номер телефона'), findsOneWidget);
    expect(find.text('Номер телефона'), findsOneWidget);
    expect(find.text('Получить код'), findsOneWidget);
  });

  testWidgets('demo login shows the SMS code field immediately after phone', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [initialDemoModeProvider.overrideWithValue(true)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const OnboardingScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('phone-input')),
      '+1 202 555 0100',
    );
    await tester.tap(find.text('Получить код'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Код из сообщения'), findsOneWidget);
    final codeField = find.byKey(const ValueKey('otp-code-input'));
    expect(codeField, findsOneWidget);
    expect(tester.widget<TextField>(codeField).controller?.text, '123456');
    expect(find.textContaining('Повторно через'), findsOneWidget);
  });
}
