/// Application-wide constants.
abstract final class AppConstants {
  static const String appName = 'Compact Games';
  static const String appVersion = '0.2.6';

  /// Identifies who owns delivery of application updates for this build.
  ///
  /// Standalone releases use the signed installer published on GitHub. Steam
  /// depot builds pass `--dart-define=COMPACT_GAMES_DISTRIBUTION=steam` so the
  /// Steam client remains the only component that replaces installed files.
  static const String distributionChannel = String.fromEnvironment(
    'COMPACT_GAMES_DISTRIBUTION',
    defaultValue: 'standalone',
  );
  // Unknown channels fail closed so a misspelled distribution value cannot
  // accidentally make a managed build replace its own files.
  static const bool selfUpdatesEnabled = distributionChannel == 'standalone';

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
