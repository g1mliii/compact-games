part of 'tray_service.dart';

enum TrayStatusMode { idle, compressing, paused, error }

@immutable
class TrayStrings {
  const TrayStrings({
    this.appName = 'PressPlay',
    this.openAppLabel = 'Open PressPlay',
    this.pauseAutoCompressionLabel = 'Pause Auto-Compression',
    this.resumeAutoCompressionLabel = 'Resume Auto-Compression',
    this.quitLabel = 'Quit',
    this.compressingLabel = 'Compressing',
    this.pausedStatusLabel = 'Paused',
    this.errorStatusLabel = 'Error',
  });

  final String appName;
  final String openAppLabel;
  final String pauseAutoCompressionLabel;
  final String resumeAutoCompressionLabel;
  final String quitLabel;
  final String compressingLabel;
  final String pausedStatusLabel;
  final String errorStatusLabel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayStrings &&
          appName == other.appName &&
          openAppLabel == other.openAppLabel &&
          pauseAutoCompressionLabel == other.pauseAutoCompressionLabel &&
          resumeAutoCompressionLabel == other.resumeAutoCompressionLabel &&
          quitLabel == other.quitLabel &&
          compressingLabel == other.compressingLabel &&
          pausedStatusLabel == other.pausedStatusLabel &&
          errorStatusLabel == other.errorStatusLabel;

  @override
  int get hashCode => Object.hash(
    appName,
    openAppLabel,
    pauseAutoCompressionLabel,
    resumeAutoCompressionLabel,
    quitLabel,
    compressingLabel,
    pausedStatusLabel,
    errorStatusLabel,
  );
}

@immutable
class TrayStatus {
  final TrayStatusMode mode;
  final String? activeGameName;
  final int? progressPercent;
  final bool autoCompressionEnabled;
  final TrayStrings strings;

  const TrayStatus({
    required this.mode,
    this.activeGameName,
    this.progressPercent,
    this.autoCompressionEnabled = false,
    this.strings = const TrayStrings(),
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayStatus &&
          mode == other.mode &&
          activeGameName == other.activeGameName &&
          progressPercent == other.progressPercent &&
          autoCompressionEnabled == other.autoCompressionEnabled &&
          strings == other.strings;

  @override
  int get hashCode => Object.hash(
    mode,
    activeGameName,
    progressPercent,
    autoCompressionEnabled,
    strings,
  );
}
