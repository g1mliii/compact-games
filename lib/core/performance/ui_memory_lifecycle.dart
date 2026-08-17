import 'dart:async';

import 'package:flutter/painting.dart';

import '../../services/cover_art_service.dart';
import '../../services/rust_bridge_service.dart';
import '../widgets/film_grain_overlay.dart';
import 'windows_working_set.dart';

enum UiMemoryTrimLevel {
  background,
  startupSettled,
  trayHide,
  pressure,
  shutdown,
}

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

  static void trim(UiMemoryTrimLevel level) {
    final imageCache = PaintingBinding.instance.imageCache;

    switch (level) {
      case UiMemoryTrimLevel.background:
        imageCache.clearLiveImages();
        trimCoverArtRuntimeCaches(aggressive: false);
        break;
      case UiMemoryTrimLevel.startupSettled:
        // Cold Flutter/graphics initialization can leave a large set of
        // one-time pages resident, especially when the first launch follows
        // display-driver resume. Keep all logical caches intact and only ask
        // Windows to evict pages that are no longer actively used.
        WindowsWorkingSet.trimCurrentProcess();
        break;
      case UiMemoryTrimLevel.trayHide:
        // Window fully hidden — prefer low tray memory over instant restore.
        // Shrink image cache limits so the framework won't re-populate while
        // hidden; configureImageCache() restores production limits on resume.
        imageCache.maximumSizeBytes = 0;
        imageCache.maximumSize = 0;
        imageCache.clear();
        imageCache.clearLiveImages();
        releaseCoverArtRuntimeCaches();
        _releaseRustVisibleOnlyCaches();
        FilmGrainOverlay.clearNoiseCache();
        WindowsWorkingSet.trimCurrentProcess();
        break;
      case UiMemoryTrimLevel.pressure:
        // Foreground memory-pressure signals must stay jank-free: reclaim
        // caches but skip `SetProcessWorkingSetSize`, which forces a hard
        // page-out that the next visible frame would have to fault back in.
        imageCache.clear();
        imageCache.clearLiveImages();
        trimCoverArtRuntimeCaches(aggressive: true);
        _releaseRustVisibleOnlyCaches();
        FilmGrainOverlay.clearNoiseCache();
        break;
      case UiMemoryTrimLevel.shutdown:
        imageCache.clear();
        imageCache.clearLiveImages();
        shutdownCoverArtSharedResources();
        _releaseRustVisibleOnlyCaches();
        FilmGrainOverlay.clearNoiseCache();
        break;
    }
  }

  /// Drops Rust-side caches that only earn their memory while the window is on
  /// screen — currently the Steam manifest index behind cover art and news.
  ///
  /// Fire-and-forget and failure-tolerant on purpose: trimming must never block
  /// a lifecycle callback, and the bridge is not loaded in tests or before
  /// startup finishes.
  static void _releaseRustVisibleOnlyCaches() {
    try {
      // An uninitialized bridge throws synchronously, so the try has to wrap the
      // call itself rather than only the returned future.
      unawaited(
        RustBridgeService.instance.clearSteamAppIdCache().catchError((_) {}),
      );
    } catch (_) {
      // Nothing to reclaim when the library was never loaded.
    }
  }
}
