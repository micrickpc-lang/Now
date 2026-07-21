import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:seychas/core/theme/app_theme.dart';
import 'package:seychas/features/auth/presentation/onboarding_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'onboarding remains usable without contacts or location permissions',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const OnboardingScreen(),
          ),
        ),
      );
      expect(find.text('Ближе — прямо сейчас'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    },
  );
}
