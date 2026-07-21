import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/theme/app_theme.dart';
import 'package:seychas/features/auth/presentation/onboarding_screen.dart';

void main() {
  testWidgets('onboarding starts with phone and privacy promise', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const OnboardingScreen(),
        ),
      ),
    );
    expect(find.text('Ближе — прямо сейчас'), findsOneWidget);
    expect(find.text('Номер телефона'), findsOneWidget);
    expect(find.text('Продолжить'), findsOneWidget);
  });
}
