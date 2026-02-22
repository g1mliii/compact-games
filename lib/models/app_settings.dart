import 'compression_algorithm.dart';

/// Application settings with JSON persistence.
class AppSettings {
  static const int currentSchemaVersion = 2;

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
  final String? steamGridDbApiKey;
  final bool inventoryAdvancedScanEnabled;

  const AppSettings({
    this.schemaVersion = currentSchemaVersion,
    this.algorithm = CompressionAlgorithm.xpress8k,
    this.autoCompress = false,
    this.cpuThreshold = 10.0,
    this.idleDurationMinutes = 5,
    this.cooldownMinutes = 5,
    this.customFolders = const [],
    this.excludedPaths = const [],
    this.notificationsEnabled = true,
    this.themeVariant = 'cinematicDesert',
    this.directStorageOverrideEnabled = false,
    this.steamGridDbApiKey,
    this.inventoryAdvancedScanEnabled = false,
  });

  /// Clamp values to safe ranges.
  AppSettings validated() {
    return AppSettings(
      schemaVersion: schemaVersion,
      algorithm: algorithm,
      autoCompress: autoCompress,
      cpuThreshold: cpuThreshold.clamp(5.0, 20.0),
      idleDurationMinutes: idleDurationMinutes.clamp(5, 30),
      cooldownMinutes: cooldownMinutes.clamp(1, 120),
      customFolders: customFolders,
      excludedPaths: excludedPaths,
      notificationsEnabled: notificationsEnabled,
      themeVariant: themeVariant.isEmpty ? 'cinematicDesert' : themeVariant,
      directStorageOverrideEnabled: directStorageOverrideEnabled,
      steamGridDbApiKey: _normalizedApiKey(steamGridDbApiKey),
      inventoryAdvancedScanEnabled: inventoryAdvancedScanEnabled,
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
    String? Function()? steamGridDbApiKey,
    bool? inventoryAdvancedScanEnabled,
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
      steamGridDbApiKey: steamGridDbApiKey != null
          ? steamGridDbApiKey()
          : this.steamGridDbApiKey,
      inventoryAdvancedScanEnabled:
          inventoryAdvancedScanEnabled ?? this.inventoryAdvancedScanEnabled,
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
    'inventoryAdvancedScanEnabled': inventoryAdvancedScanEnabled,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    return AppSettings(
      schemaVersion: schemaVersion <= 0 ? 1 : schemaVersion,
      algorithm: CompressionAlgorithm.values.firstWhere(
        (a) => a.name == json['algorithm'],
        orElse: () => CompressionAlgorithm.xpress8k,
      ),
      autoCompress: json['autoCompress'] as bool? ?? false,
      cpuThreshold: (json['cpuThreshold'] as num?)?.toDouble() ?? 10.0,
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
      steamGridDbApiKey: _normalizedApiKey(
        json['steamGridDbApiKey'] as String?,
      ),
      inventoryAdvancedScanEnabled:
          json['inventoryAdvancedScanEnabled'] as bool? ?? false,
    ).validated();
  }

  static String? _normalizedApiKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
