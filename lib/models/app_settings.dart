import 'package:flutter/foundation.dart';

import 'compression_algorithm.dart';

/// Layout mode for the home screen game library.
enum HomeViewMode { grid, list }

/// SteamGridDB lookup source for missing cover art.
enum CoverArtProviderMode { bundledProxy, userKey }

/// Application settings with JSON persistence.
@immutable
class AppSettings {
  static const int currentSchemaVersion = 6;

  final int schemaVersion;
  final CompressionAlgorithm algorithm;
  final bool autoCompress;
  final double cpuThreshold;
  final int idleDurationMinutes;
  final int cooldownMinutes;
  final List<String> customFolders;
  final List<String> excludedPaths;
  final bool notificationsEnabled;
  final String themeVariant;
  final bool directStorageOverrideEnabled;
  final int? ioParallelismOverride;
  final String? steamGridDbApiKey;
  final CoverArtProviderMode coverArtProviderMode;
  final bool inventoryAdvancedScanEnabled;
  final bool minimizeToTray;
  final HomeViewMode homeViewMode;
  final String? localeTag;
  final bool autoCheckUpdates;

  const AppSettings({
    this.schemaVersion = currentSchemaVersion,
    this.algorithm = CompressionAlgorithm.xpress8k,
    this.autoCompress = true,
    this.cpuThreshold = 40.0,
    this.idleDurationMinutes = 5,
    this.cooldownMinutes = 5,
    this.customFolders = const [],
    this.excludedPaths = const [],
    this.notificationsEnabled = true,
    this.themeVariant = 'cinematicDesert',
    this.directStorageOverrideEnabled = false,
    this.ioParallelismOverride,
    this.steamGridDbApiKey,
    this.coverArtProviderMode = CoverArtProviderMode.bundledProxy,
    this.inventoryAdvancedScanEnabled = false,
    this.minimizeToTray = true,
    this.homeViewMode = HomeViewMode.grid,
    this.localeTag,
    this.autoCheckUpdates = true,
  });

  /// Clamp values to safe ranges.
  AppSettings validated() {
    return AppSettings(
      schemaVersion: currentSchemaVersion,
      algorithm: algorithm,
      autoCompress: autoCompress,
      cpuThreshold: cpuThreshold.clamp(5.0, 80.0),
      idleDurationMinutes: idleDurationMinutes.clamp(3, 15),
      cooldownMinutes: cooldownMinutes.clamp(1, 120),
      customFolders: customFolders,
      excludedPaths: excludedPaths,
      notificationsEnabled: notificationsEnabled,
      themeVariant: themeVariant.isEmpty ? 'cinematicDesert' : themeVariant,
      directStorageOverrideEnabled: directStorageOverrideEnabled,
      ioParallelismOverride: _validatedIoOverride(ioParallelismOverride),
      steamGridDbApiKey: _normalizedApiKey(steamGridDbApiKey),
      coverArtProviderMode: coverArtProviderMode,
      inventoryAdvancedScanEnabled: inventoryAdvancedScanEnabled,
      minimizeToTray: minimizeToTray,
      homeViewMode: homeViewMode,
      localeTag: _normalizedLocaleTag(localeTag),
      autoCheckUpdates: autoCheckUpdates,
    );
  }

  AppSettings copyWith({
    CompressionAlgorithm? algorithm,
    bool? autoCompress,
    double? cpuThreshold,
    int? idleDurationMinutes,
    int? cooldownMinutes,
    List<String>? customFolders,
    List<String>? excludedPaths,
    bool? notificationsEnabled,
    String? themeVariant,
    bool? directStorageOverrideEnabled,
    int? Function()? ioParallelismOverride,
    String? Function()? steamGridDbApiKey,
    CoverArtProviderMode? coverArtProviderMode,
    bool? inventoryAdvancedScanEnabled,
    bool? minimizeToTray,
    HomeViewMode? homeViewMode,
    String? Function()? localeTag,
    bool? autoCheckUpdates,
  }) {
    return AppSettings(
      schemaVersion: schemaVersion,
      algorithm: algorithm ?? this.algorithm,
      autoCompress: autoCompress ?? this.autoCompress,
      cpuThreshold: cpuThreshold ?? this.cpuThreshold,
      idleDurationMinutes: idleDurationMinutes ?? this.idleDurationMinutes,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      customFolders: customFolders ?? this.customFolders,
      excludedPaths: excludedPaths ?? this.excludedPaths,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      themeVariant: themeVariant ?? this.themeVariant,
      directStorageOverrideEnabled:
          directStorageOverrideEnabled ?? this.directStorageOverrideEnabled,
      ioParallelismOverride: ioParallelismOverride != null
          ? ioParallelismOverride()
          : this.ioParallelismOverride,
      steamGridDbApiKey: steamGridDbApiKey != null
          ? steamGridDbApiKey()
          : this.steamGridDbApiKey,
      coverArtProviderMode: coverArtProviderMode ?? this.coverArtProviderMode,
      inventoryAdvancedScanEnabled:
          inventoryAdvancedScanEnabled ?? this.inventoryAdvancedScanEnabled,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      homeViewMode: homeViewMode ?? this.homeViewMode,
      localeTag: localeTag != null ? localeTag() : this.localeTag,
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'algorithm': algorithm.name,
    'autoCompress': autoCompress,
    'cpuThreshold': cpuThreshold,
    'idleDurationMinutes': idleDurationMinutes,
    'cooldownMinutes': cooldownMinutes,
    'customFolders': customFolders,
    'excludedPaths': excludedPaths,
    'notificationsEnabled': notificationsEnabled,
    'themeVariant': themeVariant,
    'directStorageOverrideEnabled': directStorageOverrideEnabled,
    'ioParallelismOverride': ioParallelismOverride,
    'coverArtProviderMode': coverArtProviderMode.name,
    'inventoryAdvancedScanEnabled': inventoryAdvancedScanEnabled,
    'minimizeToTray': minimizeToTray,
    'homeViewMode': homeViewMode.name,
    'localeTag': localeTag,
    'autoCheckUpdates': autoCheckUpdates,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    final steamGridDbApiKey = _normalizedApiKey(
      json['steamGridDbApiKey'] as String?,
    );
    return AppSettings(
      schemaVersion: schemaVersion <= 0 ? 1 : schemaVersion,
      algorithm: CompressionAlgorithm.values.firstWhere(
        (a) => a.name == json['algorithm'],
        orElse: () => CompressionAlgorithm.xpress8k,
      ),
      autoCompress: json['autoCompress'] as bool? ?? false,
      cpuThreshold: (json['cpuThreshold'] as num?)?.toDouble() ?? 40.0,
      idleDurationMinutes: json['idleDurationMinutes'] as int? ?? 5,
      cooldownMinutes: json['cooldownMinutes'] as int? ?? 5,
      customFolders:
          (json['customFolders'] as List<dynamic>?)?.cast<String>().toList() ??
          const [],
      excludedPaths:
          (json['excludedPaths'] as List<dynamic>?)?.cast<String>().toList() ??
          const [],
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      themeVariant: json['themeVariant'] as String? ?? 'cinematicDesert',
      directStorageOverrideEnabled:
          json['directStorageOverrideEnabled'] as bool? ?? false,
      ioParallelismOverride: _toIntOrNull(json['ioParallelismOverride']),
      steamGridDbApiKey: steamGridDbApiKey,
      coverArtProviderMode: _coverArtProviderModeFromJson(
        json['coverArtProviderMode'],
        legacyApiKey: steamGridDbApiKey,
      ),
      inventoryAdvancedScanEnabled:
          json['inventoryAdvancedScanEnabled'] as bool? ?? false,
      minimizeToTray: json['minimizeToTray'] as bool? ?? true,
      homeViewMode: HomeViewMode.values.firstWhere(
        (v) => v.name == json['homeViewMode'],
        orElse: () => HomeViewMode.grid,
      ),
      localeTag: _normalizedLocaleTag(json['localeTag'] as String?),
      autoCheckUpdates: json['autoCheckUpdates'] as bool? ?? true,
    ).validated();
  }

  static String? _normalizedApiKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static CoverArtProviderMode _coverArtProviderModeFromJson(
    Object? value, {
    required String? legacyApiKey,
  }) {
    if (value is String) {
      for (final mode in CoverArtProviderMode.values) {
        if (mode.name == value) {
          return mode;
        }
      }
    }
    return legacyApiKey == null
        ? CoverArtProviderMode.bundledProxy
        : CoverArtProviderMode.userKey;
  }

  static int? _toIntOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static int? _validatedIoOverride(int? value) {
    if (value == null) {
      return null;
    }
    return value.clamp(1, 16);
  }

  static String? _normalizedLocaleTag(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.replaceAll('_', '-');
  }
}
