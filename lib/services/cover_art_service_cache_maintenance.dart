part of 'cover_art_service.dart';

const Duration _cacheEvictionCooldown = Duration(seconds: 45);
DateTime _lastCacheEvictionRun = DateTime.fromMillisecondsSinceEpoch(0);
Future<void>? _cacheEvictionInFlight;
bool _cacheEvictionQueued = false;

void _resetCacheEvictionScheduler() {
  _cacheEvictionQueued = false;
  _cacheEvictionInFlight = null;
  _lastCacheEvictionRun = DateTime.fromMillisecondsSinceEpoch(0);
}

extension _CoverArtServiceCacheMaintenance on CoverArtService {
  void _scheduleCacheEviction(Directory cacheDir, {bool force = false}) {
    if (_cacheEvictionInFlight != null) {
      _cacheEvictionQueued = true;
      return;
    }

    if (!force &&
        DateTime.now().difference(_lastCacheEvictionRun) <
            _cacheEvictionCooldown) {
      return;
    }

    _cacheEvictionInFlight = _runScheduledCacheEviction(cacheDir);
  }

  Future<void> _runScheduledCacheEviction(Directory cacheDir) async {
    try {
      await _evictCacheIfNeeded(cacheDir);
    } finally {
      _lastCacheEvictionRun = DateTime.now();
      _cacheEvictionInFlight = null;
      if (_cacheEvictionQueued) {
        _cacheEvictionQueued = false;
        _scheduleCacheEviction(cacheDir, force: true);
      }
    }
  }
}
