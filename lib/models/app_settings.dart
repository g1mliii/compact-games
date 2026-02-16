import 'compression_algorithm.dart';

/// Application settings with JSON persistence.
class AppSettings {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final CompressionAlgorithm algorithm;
  final bool autoCompress;
  final double cpuThreshold;
  final int idleDurationMinutes;
  final int cooldownMinutes;
  final List<String> customFolders;
  final List<String> excludedPaths;

  const AppSettings({
    this.schemaVersion = currentSchemaVersion,
    this.algorithm = CompressionAlgorithm.xpress8k,
    this.autoCompress = false,
    this.cpuThreshold = 10.0,
    this.idleDurationMinutes = 2,
    this.cooldownMinutes = 5,
    this.customFolders = const [],
    this.excludedPaths = const [],
  });

  /// Clamp values to safe ranges.
  AppSettings validated() {
    return AppSettings(
      schemaVersion: schemaVersion,
      algorithm: algorithm,
      autoCompress: autoCompress,
      cpuThreshold: cpuThreshold.clamp(1.0, 100.0),
      idleDurationMinutes: idleDurationMinutes.clamp(1, 60),
      cooldownMinutes: cooldownMinutes.clamp(1, 120),
      customFolders: customFolders,
      excludedPaths: excludedPaths,
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
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      algorithm: CompressionAlgorithm.values.firstWhere(
        (a) => a.name == json['algorithm'],
        orElse: () => CompressionAlgorithm.xpress8k,
      ),
      autoCompress: json['autoCompress'] as bool? ?? false,
      cpuThreshold: (json['cpuThreshold'] as num?)?.toDouble() ?? 10.0,
      idleDurationMinutes: json['idleDurationMinutes'] as int? ?? 2,
      cooldownMinutes: json['cooldownMinutes'] as int? ?? 5,
      customFolders: (json['customFolders'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          const [],
      excludedPaths: (json['excludedPaths'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          const [],
    ).validated();
  }
}
