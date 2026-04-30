/// Application-wide constants.
abstract final class AppConstants {
  static const String appName = 'Compact Games';
  static const String appVersion = '0.1.8';

  // Window
  static const double minWindowWidth = 900;
  static const double minWindowHeight = 600;
  static const double defaultWindowWidth = 1200;
  static const double defaultWindowHeight = 800;

  // Grid layout
  static const double cardMinWidth = 240;
  static const double cardMaxWidth = 288;
  static const double gridSpacing = 16;

  // Cover art
  static const String coverCacheDir = 'covers';
  static const int coverCacheDays = 30;
  static const double coverAspectRatio = 2 / 3;

  // Progress updates
  static const int progressUpdateIntervalMs = 100;

  // Automation defaults
  static const double defaultCpuThreshold = 40.0;
  static const int defaultIdleDurationMinutes = 5;
  static const int defaultCooldownMinutes = 5;
}
