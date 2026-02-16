import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'film_grain_overlay.dart';

class CinematicBackground extends StatelessWidget {
  const CinematicBackground({required this.child, super.key});

  static const Key staticLayersKey = ValueKey<String>(
    'cinematic-background-static-layers',
  );

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.horizonGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            key: staticLayersKey,
            child: _CinematicBackgroundLayers(),
          ),
          child,
        ],
      ),
    );
  }
}

class _CinematicBackgroundLayers extends StatelessWidget {
  const _CinematicBackgroundLayers();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        _GlowOrb(
          alignment: Alignment(-0.85, -0.92),
          radius: 320,
          color: AppColors.richGold,
          opacity: 0.12,
        ),
        _GlowOrb(
          alignment: Alignment(0.88, -1.0),
          radius: 280,
          color: AppColors.desertGold,
          opacity: 0.08,
        ),
        _GlowOrb(
          alignment: Alignment(0.0, 1.1),
          radius: 520,
          color: AppColors.burntSienna,
          opacity: 0.1,
        ),
        FilmGrainOverlay(opacity: 0.028, density: 0.11),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.alignment,
    required this.radius,
    required this.color,
    required this.opacity,
  });

  final Alignment alignment;
  final double radius;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: SizedBox(
          width: radius,
          height: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: opacity),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
