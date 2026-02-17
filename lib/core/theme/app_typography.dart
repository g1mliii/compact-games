import 'package:flutter/material.dart';
import 'app_colors.dart';

/// PressPlay typography system using Inter and JetBrains Mono.
abstract final class AppTypography {
  static const String bodyFontFamily = 'Inter';
  static const String monoFontFamily = 'JetBrainsMono';
  static const List<String> bodyFontFallback = <String>['sans-serif'];
  static const List<String> monoFontFallback = <String>['monospace'];

  static const TextStyle headingLarge = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle headingMedium = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle headingSmall = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  static const TextStyle label = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle monoSmall = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle monoMedium = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle statValue = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}
