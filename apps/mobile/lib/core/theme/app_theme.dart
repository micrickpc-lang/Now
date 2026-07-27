import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF0D1020);
  static const surface = Color(0xFF171B31);
  static const elevatedSurface = Color(0xFF202640);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const elevatedSurfaceLight = Color(0xFFECEEF7);
  static const canvasLight = Color(0xFFF5F6FB);
  static const text = Color(0xFFF7F7FC);
  static const textDark = Color(0xFF16182A);
  static const muted = Color(0xFFA9AFC3);
  static const mutedDark = Color(0xFF686E83);
  static const border = Color(0xFF2A304D);
  static const borderLight = Color(0xFFD8DCE9);
  static const violet = Color(0xFF8B7CFF);
  static const coral = Color(0xFFFF7B86);
  static const mint = Color(0xFF6DE6C3);
  static const privacy = Color(0xFF59C6FF);
  static const warning = Color(0xFFFFBD66);
  static const danger = Color(0xFFFF6573);
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
  static const pill = 999.0;
}

abstract final class AppDuration {
  static const quick = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
}

abstract final class AppTheme {
  static ThemeData get dark =>
      _theme(Brightness.dark, AppColors.ink, AppColors.text);
  static ThemeData get light =>
      _theme(Brightness.light, AppColors.canvasLight, AppColors.textDark);

  static ThemeData _theme(
    Brightness brightness,
    Color background,
    Color foreground,
  ) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? AppColors.surface : AppColors.surfaceLight;
    final elevatedSurface = dark
        ? AppColors.elevatedSurface
        : AppColors.elevatedSurfaceLight;
    final muted = dark ? AppColors.muted : AppColors.mutedDark;
    final border = dark ? AppColors.border : AppColors.borderLight;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.violet,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.violet,
          onPrimary: Colors.white,
          secondary: AppColors.coral,
          tertiary: AppColors.mint,
          surface: surface,
          surfaceContainer: elevatedSurface,
          surfaceContainerHigh: elevatedSurface,
          onSurface: foreground,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: border,
          error: AppColors.danger,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      textTheme:
          (dark
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
                  fontSize: 32,
                  height: 38 / 32,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
                headlineMedium: TextStyle(
                  fontSize: 24,
                  height: 30 / 24,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
                titleLarge: TextStyle(
                  fontSize: 20,
                  height: 26 / 20,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
                bodyLarge: TextStyle(
                  fontSize: 16,
                  height: 24 / 16,
                  color: foreground,
                ),
                labelLarge: TextStyle(
                  fontSize: 14,
                  height: 18 / 14,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
              ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 20,
          height: 26 / 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: elevatedSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          backgroundColor: AppColors.violet,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: AppColors.violet, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevatedSurface,
        selectedColor: AppColors.violet,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        labelStyle: TextStyle(color: foreground, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: surface,
        indicatorColor: AppColors.violet.withValues(alpha: .22),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: muted, fontSize: 11),
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
