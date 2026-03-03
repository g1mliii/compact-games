import 'package:flutter/painting.dart';

import '../../services/cover_art_service.dart';
import '../widgets/film_grain_overlay.dart';

enum UiMemoryTrimLevel { background, trayHide, pressure, shutdown }

/// Centralized memory trim hooks for desktop lifecycle events.
abstract final class UiMemoryLifecycle {
  /// Current decoded image cache usage in bytes (for debug overlay).
  static int get currentImageCacheBytes =>
      PaintingBinding.instance.imageCache.currentSizeBytes;

  /// Current decoded image cache entry count (for debug overlay).
  static int get currentImageCacheCount =>
      PaintingBinding.instance.imageCache.currentSize;

  static void trim(UiMemoryTrimLevel level) {
    final imageCache = PaintingBinding.instance.imageCache;

    switch (level) {
      case UiMemoryTrimLevel.background:
        imageCache.clearLiveImages();
        trimCoverArtRuntimeCaches(aggressive: false);
        break;
      case UiMemoryTrimLevel.trayHide:
        // Window fully hidden — release all cached images and grain textures.
        // Keeps cover-art metadata caches (non-aggressive) so restore is fast.
        imageCache.clear();
        imageCache.clearLiveImages();
        trimCoverArtRuntimeCaches(aggressive: false);
        FilmGrainOverlay.clearNoiseCache();
        break;
      case UiMemoryTrimLevel.pressure:
        imageCache.clear();
        imageCache.clearLiveImages();
        trimCoverArtRuntimeCaches(aggressive: true);
        FilmGrainOverlay.clearNoiseCache();
        break;
      case UiMemoryTrimLevel.shutdown:
        imageCache.clear();
        imageCache.clearLiveImages();
        shutdownCoverArtSharedResources();
        FilmGrainOverlay.clearNoiseCache();
        break;
    }
  }
}
