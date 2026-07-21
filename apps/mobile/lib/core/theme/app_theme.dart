import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF0D1020);
  static const surface = Color(0xFF171B31);
  static const surfaceLight = Color(0xFFF3F1FA);
  static const text = Color(0xFFF7F7FC);
  static const textDark = Color(0xFF171727);
  static const muted = Color(0xFFAEB3C7);
  static const violet = Color(0xFF8B7CFF);
  static const coral = Color(0xFFFF7B86);
  static const mint = Color(0xFF6DE6C3);
  static const danger = Color(0xFFFF5570);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class AppRadii {
  static const sm = 12.0;
  static const md = 20.0;
  static const lg = 28.0;
}

abstract final class AppDuration {
  static const quick = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
}

abstract final class AppTheme {
  static ThemeData get dark =>
      _theme(Brightness.dark, AppColors.ink, AppColors.text);
  static ThemeData get light =>
      _theme(Brightness.light, const Color(0xFFF7F5FC), AppColors.textDark);

  static ThemeData _theme(
    Brightness brightness,
    Color background,
    Color foreground,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.violet,
      brightness: brightness,
      primary: AppColors.violet,
      secondary: AppColors.mint,
      tertiary: AppColors.coral,
      surface: brightness == Brightness.dark
          ? AppColors.surface
          : AppColors.surfaceLight,
      error: AppColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'sans-serif',
      textTheme:
          (brightness == Brightness.dark
                  ? Typography.material2021(
                      platform: TargetPlatform.android,
                    ).white
                  : Typography.material2021(
                      platform: TargetPlatform.android,
                    ).black)
              .apply(
                bodyColor: foreground,
                displayColor: foreground,
                fontFamily: 'sans-serif',
              )
              .copyWith(
                displaySmall: TextStyle(
                  fontSize: 40,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  color: foreground,
                ),
                headlineMedium: TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                  color: foreground,
                ),
                titleLarge: TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface.withValues(alpha: .82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .35)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface.withValues(alpha: .7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
