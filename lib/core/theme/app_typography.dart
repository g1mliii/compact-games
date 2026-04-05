import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Compact Games typography system using platform system fonts.
abstract final class AppTypography {
  static const String bodyFontFamily = 'Segoe UI Variable Text';
  static const String monoFontFamily = 'Consolas';
  static const List<String> bodyFontFallback = <String>[
    'Segoe UI',
    'SF Pro Text',
    'Roboto',
    'sans-serif',
  ];
  static const List<String> monoFontFallback = <String>[
    'Cascadia Mono',
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'monospace',
  ];

  static const TextStyle headingLarge = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );

  static const TextStyle headingMedium = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );

  static const TextStyle headingSmall = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.05,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.12,
  );

  static const TextStyle label = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: bodyFontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.35,
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
