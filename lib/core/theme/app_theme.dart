import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

const double appDesktopControlMin = 36.0;
const double appDesktopFrequentActionMin = 44.0;
const double appDesktopMenuRowMin = 38.0;
const BorderRadius appPanelRadius = BorderRadius.all(Radius.circular(16));

/// Shared interaction overlay used across buttons and desktop row surfaces.
final appInteractionOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
  if (states.contains(WidgetState.pressed)) {
    return AppColors.textPrimary.withValues(alpha: 0.08);
  }
  if (states.contains(WidgetState.hovered) ||
      states.contains(WidgetState.focused)) {
    return AppColors.textPrimary.withValues(alpha: 0.05);
  }
  return null;
});

final appFocusInteractionOverlay = WidgetStateProperty.resolveWith<Color?>((
  states,
) {
  if (states.contains(WidgetState.pressed)) {
    return AppColors.focusFill.withValues(alpha: 0.18);
  }
  if (states.contains(WidgetState.hovered) ||
      states.contains(WidgetState.focused)) {
    return AppColors.focusFill;
  }
  return null;
});

BoxDecoration buildAppPanelDecoration({
  BorderRadius borderRadius = appPanelRadius,
  bool emphasized = false,
}) {
  return BoxDecoration(
    gradient: emphasized ? AppColors.heroGradient : AppColors.panelGradient,
    borderRadius: borderRadius,
    border: Border.all(
      color: emphasized ? AppColors.border : AppColors.borderSubtle,
    ),
  );
}

BoxDecoration buildAppSurfaceDecoration({
  BorderRadius borderRadius = appPanelRadius,
  bool selected = false,
}) {
  return BoxDecoration(
    color: AppColors.surfaceCard.withValues(alpha: 0.9),
    borderRadius: borderRadius,
    border: Border.all(
      color: selected ? AppColors.selectionBorder : AppColors.borderSubtle,
    ),
  );
}

/// Builds the PressPlay cinematic desert theme.
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    // Kill ink splashes globally — use overlayColor for hover/press feedback.
    // This eliminates InkSparkle shader compilation jank and repaint storms.
    splashFactory: NoSplash.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.nightDune,
      secondary: AppColors.accentMuted,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.textPrimary,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: AppColors.borderSubtle, width: 1),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.burntSienna,
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ).copyWith(overlayColor: appInteractionOverlay),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ).copyWith(overlayColor: appInteractionOverlay),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
      ).copyWith(overlayColor: appInteractionOverlay),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom().copyWith(
        overlayColor: appInteractionOverlay,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderSubtle),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(overlayColor: appInteractionOverlay),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.accent;
        }
        return AppColors.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.accentMuted;
        }
        return AppColors.surfaceElevated;
      }),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        gradient: AppColors.panelGradient,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceElevated.withValues(alpha: 0.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.focusRing),
      ),
      hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
    ),
    textTheme: const TextTheme(
      titleLarge: AppTypography.headingLarge,
      titleMedium: AppTypography.headingMedium,
      titleSmall: AppTypography.headingSmall,
      bodyLarge: AppTypography.bodyLarge,
      bodyMedium: AppTypography.bodyMedium,
      bodySmall: AppTypography.bodySmall,
      labelMedium: AppTypography.label,
    ),
  );
}
