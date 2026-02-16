import 'package:flutter/material.dart';

/// PressPlay color palette.
/// Cinematic desert palette with deep horizon tones and warm highlights.
abstract final class AppColors {
  // Core palette
  static const Color deepHorizonBlue = Color(0xFF1E3042);
  static const Color nightDune = Color(0xFF121B24);
  static const Color sunBleachedWhite = Color(0xFFF3E9D7);
  static const Color desertSand = Color(0xFFD8C3A0);
  static const Color burntSienna = Color(0xFFB45A3C);
  static const Color desertGold = Color(0xFFC89B3C);
  static const Color richGold = Color(0xFFE2BE63);

  // Background layers
  static const Color background = nightDune;
  static const Color surface = Color(0xFF192532);
  static const Color surfaceVariant = Color(0xFF223243);
  static const Color surfaceElevated = Color(0xFF2A3B4E);

  // Borders
  static const Color border = Color(0x66D8C3A0);
  static const Color borderSubtle = Color(0x33D8C3A0);

  // Text
  static const Color textPrimary = sunBleachedWhite;
  static const Color textSecondary = desertSand;
  static const Color textMuted = Color(0xB39A8667);

  // Accent / brand
  static const Color accent = richGold;
  static const Color accentHover = Color(0xFFF4D084);
  static const Color accentMuted = desertGold;

  // Status
  static const Color success = Color(0xFF88C47B);
  static const Color warning = Color(0xFFD7A14D);
  static const Color error = Color(0xFFDA7453);
  static const Color info = Color(0xFF8CB6D8);

  // Compression-specific
  static const Color compressed = desertGold;
  static const Color notCompressed = Color(0xFF9B8B73);
  static const Color directStorage = burntSienna;
  static const Color compressing = richGold;

  // Cinematic gradients
  static const LinearGradient horizonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [deepHorizonBlue, nightDune],
  );

  static const LinearGradient panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surfaceVariant, surface],
  );

  static const LinearGradient progressGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [desertGold, burntSienna],
  );
}
