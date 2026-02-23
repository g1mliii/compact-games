import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Lightweight deterministic grain effect for subtle cinematic texture.
class FilmGrainOverlay extends StatelessWidget {
  const FilmGrainOverlay({
    this.opacity = 0.035,
    this.density = 0.14,
    super.key,
  });

  final double opacity;
  final double density;

  /// Releases cached grain point sets; useful for low-memory/background trims.
  static void clearNoiseCache() => _NoisePointCache.clear();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _FilmGrainPainter(opacity: opacity, density: density),
          isComplex: true,
          willChange: false,
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FilmGrainPainter extends CustomPainter {
  const _FilmGrainPainter({required this.opacity, required this.density});

  final double opacity;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    final points = _NoisePointCache.pointsFor(
      width: size.width.ceil(),
      height: size.height.ceil(),
      density: density,
    );
    if (points.isEmpty) {
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0));
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant _FilmGrainPainter oldDelegate) {
    return oldDelegate.opacity != opacity || oldDelegate.density != density;
  }
}

abstract final class _NoisePointCache {
  static const int _step = 6;
  static const int _sizeBucket = 96;
  static const int _maxEntries = 12;
  static final LinkedHashMap<_NoiseCacheKey, List<Offset>> _cache =
      LinkedHashMap<_NoiseCacheKey, List<Offset>>();

  static List<Offset> pointsFor({
    required int width,
    required int height,
    required double density,
  }) {
    if (width <= 0 || height <= 0 || density <= 0) {
      return const <Offset>[];
    }

    final bucketedWidth = _bucketUp(width);
    final bucketedHeight = _bucketUp(height);
    final key = _NoiseCacheKey(
      width: bucketedWidth,
      height: bucketedHeight,
      densityPermille: (density * 1000).round().clamp(1, 1000),
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    final generated = <Offset>[];
    for (var y = 0; y < bucketedHeight; y += _step) {
      for (var x = 0; x < bucketedWidth; x += _step) {
        final hash = ((x * 73856093) ^ (y * 19349663)) & 0xFF;
        final level = hash / 255.0;
        if (level > density) {
          continue;
        }
        generated.add(Offset(x.toDouble(), y.toDouble()));
      }
    }

    _cache[key] = generated;
    if (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return generated;
  }

  static int _bucketUp(int value) {
    return ((value + _sizeBucket - 1) ~/ _sizeBucket) * _sizeBucket;
  }

  static void clear() {
    _cache.clear();
  }
}

class _NoiseCacheKey {
  const _NoiseCacheKey({
    required this.width,
    required this.height,
    required this.densityPermille,
  });

  final int width;
  final int height;
  final int densityPermille;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _NoiseCacheKey &&
            width == other.width &&
            height == other.height &&
            densityPermille == other.densityPermille;
  }

  @override
  int get hashCode => Object.hash(width, height, densityPermille);
}
