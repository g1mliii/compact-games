import 'package:flutter/painting.dart';

import '../../services/cover_art_service.dart';
import '../widgets/film_grain_overlay.dart';

enum UiMemoryTrimLevel { background, trayHide, pressure, shutdown }

/// Centralized memory trim hooks for desktop lifecycle events.
abstract final class UiMemoryLifecycle {
  /// Hard cap on decoded image bytes held by Flutter's [ImageCache].
  static const int imageCacheMaxBytes = 50 * 1024 * 1024;

  /// Hard cap on decoded image entries held by Flutter's [ImageCache].
  static const int imageCacheMaxEntries = 300;

  /// Apply the production image cache limits. Call once from `main()`.
  static void configureImageCache() {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSizeBytes = imageCacheMaxBytes;
    imageCache.maximumSize = imageCacheMaxEntries;
  }

  /// Current decoded image cache usage in bytes. Exposed for memory-aware
  /// production logic (e.g. gating `wantKeepAlive` on scroll-heavy widgets).
  static int get currentImageCacheBytes =>
      PaintingBinding.instance.imageCache.currentSizeBytes;

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
