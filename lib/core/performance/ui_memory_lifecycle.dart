import 'package:flutter/painting.dart';

import '../../services/cover_art_service.dart';
import '../widgets/film_grain_overlay.dart';

enum UiMemoryTrimLevel { background, pressure, shutdown }

/// Centralized memory trim hooks for desktop lifecycle events.
abstract final class UiMemoryLifecycle {
  static void trim(UiMemoryTrimLevel level) {
    final imageCache = PaintingBinding.instance.imageCache;

    switch (level) {
      case UiMemoryTrimLevel.background:
        imageCache.clearLiveImages();
        trimCoverArtRuntimeCaches(aggressive: false);
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
