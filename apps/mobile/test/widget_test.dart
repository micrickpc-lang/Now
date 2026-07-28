import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/theme/app_theme.dart';
import 'package:seychas/features/auth/presentation/onboarding_screen.dart';

void main() {
  testWidgets('authentication starts with email and Google entry points', (
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

    expect(find.text('Sign in to Seychas'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
