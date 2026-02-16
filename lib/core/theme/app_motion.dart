import 'package:flutter/material.dart';

/// Centralized motion tokens for cinematic-but-restrained interactions.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve decelerateCurve = Curves.easeOutQuad;
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  static bool animationsEnabled(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    return !(mediaQuery?.disableAnimations ?? false);
  }
}
