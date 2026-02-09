import 'package:flutter/material.dart';

/// PressPlay color palette.
/// Dark-mode-first design inspired by modern game launchers (Steam, Discord).
abstract final class AppColors {
  // Background layers (darkest to lightest)
  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceVariant = Color(0xFF1C2128);
  static const Color surfaceElevated = Color(0xFF21262D);

  // Borders
  static const Color border = Color(0xFF30363D);
  static const Color borderSubtle = Color(0xFF21262D);

  // Text
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF484F58);

  // Accent / brand
  static const Color accent = Color(0xFF58A6FF);
  static const Color accentHover = Color(0xFF79C0FF);
  static const Color accentMuted = Color(0xFF1F6FEB);

  // Status
  static const Color success = Color(0xFF3FB950);
  static const Color warning = Color(0xFFD29922);
  static const Color error = Color(0xFFF85149);
  static const Color info = Color(0xFF58A6FF);

  // Compression-specific
  static const Color compressed = Color(0xFF3FB950);
  static const Color notCompressed = Color(0xFF8B949E);
  static const Color directStorage = Color(0xFFF85149);
  static const Color compressing = Color(0xFF58A6FF);
}
