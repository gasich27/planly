import 'package:flutter/material.dart';

// 🎨 UI-CUSTOMIZATION: Меняй значения здесь, чтобы изменить стиль всего приложения
class AppColors {
  static const primary = Color(0xFF6366F1);
  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
}

class AppTypography {
  static const String family = 'Steppe';

  static double _tracking(double fontSize) => -fontSize * 0.06;

  static TextStyle get headlineLarge => TextStyle(
        fontFamily: family,
        fontSize: 28,
        fontWeight: FontWeight.w300,
        letterSpacing: _tracking(28),
        color: AppColors.textPrimary,
        height: 1.15,
      );

  static TextStyle get headlineMedium => TextStyle(
        fontFamily: family,
        fontSize: 22,
        fontWeight: FontWeight.w300,
        letterSpacing: _tracking(22),
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get titleLarge => TextStyle(
        fontFamily: family,
        fontSize: 18,
        fontWeight: FontWeight.w300,
        letterSpacing: _tracking(18),
        color: AppColors.textPrimary,
        height: 1.25,
      );

  static TextStyle get bodyLarge => TextStyle(
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w300,
        letterSpacing: _tracking(16),
        color: AppColors.textPrimary,
        height: 1.45,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w300,
        letterSpacing: _tracking(14),
        color: AppColors.textSecondary,
        height: 1.45,
      );
}

class AppSpacing {
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadius {
  static const double card = 16;
  static const double button = 12;
  static const double input = 12;
}
