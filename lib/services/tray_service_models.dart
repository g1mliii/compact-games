part of 'tray_service.dart';

enum TrayStatusMode { idle, compressing, paused, error }

class TrayStatus {
  final TrayStatusMode mode;
  final String? activeGameName;
  final int? progressPercent;
  final bool autoCompressionEnabled;

  const TrayStatus({
    required this.mode,
    this.activeGameName,
    this.progressPercent,
    this.autoCompressionEnabled = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayStatus &&
          mode == other.mode &&
          activeGameName == other.activeGameName &&
          progressPercent == other.progressPercent &&
          autoCompressionEnabled == other.autoCompressionEnabled;

  @override
  int get hashCode => Object.hash(
    mode,
    activeGameName,
    progressPercent,
    autoCompressionEnabled,
  );
}
