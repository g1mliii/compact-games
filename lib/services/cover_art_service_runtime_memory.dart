part of 'cover_art_service.dart';

const int _backgroundMemoryCacheEntries = 120;
const int _backgroundEstimateHintEntries = 220;
const int _backgroundSteamManifestCacheEntries = 3;
const int _backgroundCoverQualityCacheEntries = 320;

void trimCoverArtRuntimeCaches({required bool aggressive}) {
  if (aggressive) {
    CoverArtService._memoryCache.clear();
    CoverArtService._estimateHints.clear();
    CoverArtService._steamManifestCache.clear();
    CoverArtService._coverQualityPathCache.clear();
    _clearCoverArtApiLookupCaches();
    return;
  }

  CoverArtService._trimLru(
    CoverArtService._memoryCache,
    _backgroundMemoryCacheEntries,
  );
  CoverArtService._trimLru(
    CoverArtService._estimateHints,
    _backgroundEstimateHintEntries,
  );
  CoverArtService._trimLru(
    CoverArtService._steamManifestCache,
    _backgroundSteamManifestCacheEntries,
  );
  CoverArtService._trimLru(
    CoverArtService._coverQualityPathCache,
    _backgroundCoverQualityCacheEntries,
  );
}

void releaseCoverArtRuntimeCaches() {
  trimCoverArtRuntimeCaches(aggressive: true);
  _resetCacheEvictionScheduler();
}

void shutdownCoverArtSharedResources() {
  releaseCoverArtRuntimeCaches();
  CoverArtService._inFlight.clear();
  CoverArtService._cachedCacheDir = null;
  _resetCoverArtApiQueueState();
  _disposeCoverArtApiHttpClient();
}
