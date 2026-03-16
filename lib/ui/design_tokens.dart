// lib/ui/design_tokens.dart
// App surface and accent colors for shell and workspace.

import 'package:flutter/material.dart';

abstract class AppSurfaces {
  static Color get pageBg => const Color(0xFFF5F5F5);
  static Color get workspaceBg => const Color(0xFFFAFAFA);
  static Color get shellBg => const Color(0xFFFFFFFF);
  static Color get divider => const Color(0xFFE0E0E0);
  static Color get cardBorder => const Color(0xFFE0E0E0);
}

abstract class AppAccent {
  static Color get primary => const Color(0xFF1976D2);
  static Color get primarySoft => const Color(0xFFE3F2FD);
  static Color get primaryHover => const Color(0xFFBBDEFB);
}

abstract class AppColors {
  static const Color primary = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFFE3F2FD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);
  static const Color onSurface = Color(0xFF1C1B1F);
  static const Color onSurfaceVariant = Color(0xFF49454F);
  static const Color outline = Color(0xFF79747E);
  static const Color outlineVariant = Color(0xFFCAC4D0);
  static const Color error = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFED6C02);
  static const Color info = Color(0xFF0288D1);
  static const Color settingsCardBorder = Color(0xFFE0E0E0);
  static const Color inputFill = Color(0xFFF5F5F5);
  static const Color settingsPageBg = Color(0xFFF8F9FA);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color subtleBorder = Color(0xFFE8E8E8);
}

/// Public booking / landing page palette (live aesthetic: light grey bg, purple CTA).
abstract class PublicBookingColors {
  static const Color background = Color(0xFFF5F5F7);
  static const Color primaryButton = Color(0xFF7A4F9F);
  static const Color cardSurface = Color(0xFFFFFFFF);
}

/// Unified theme for the public booking flow (intro, booking grid, details, confirmation).
/// Use in PublicApp and when building public routes in the main app so shell, app bar,
/// and cards feel like one product.
abstract class PublicTheme {
  static ThemeData get data {
    const seed = PublicBookingColors.primaryButton;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: seed,
      surface: PublicBookingColors.background,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'OpenSans',
      colorScheme: scheme.copyWith(
        surface: PublicBookingColors.cardSurface,
        surfaceContainerHighest: PublicBookingColors.background,
      ),
      scaffoldBackgroundColor: PublicBookingColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: PublicBookingColors.cardSurface,
        foregroundColor: Color(0xFF1C1B1F),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        color: PublicBookingColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PublicBookingColors.primaryButton,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.element),
          ),
        ),
      ),
    );
  }
}

abstract class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double element = 8;
  static const double card = 12;
  /// Outer workspace surface (larger than inner regions for unified shell).
  static const double workspace = 20;
}

/// Soft shadow for elevated cards (premium feel without heavy elevation).
abstract class AppShadows {
  static List<BoxShadow> get cardElevated => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];
  static List<BoxShadow> get saveBarTop => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ];
}

abstract class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double screenPadding = 24;
  static const double sectionGap = 24;
  static const double elementGap = 12;
}

abstract class AppSizes {
  static const double iconSm = 16;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double buttonHeight = 48;
  static const double inputHeight = 56;
  static const double cardMaxWidth = 600;
  static const double maxContentWidth = 720;
  static const double welcomeMaxWidth = 480;
  static const double settingsFormMaxWidth = 680;
  /// General clinic settings form column (premium narrow layout).
  static const double generalSettingsMaxWidth = 640;
}
