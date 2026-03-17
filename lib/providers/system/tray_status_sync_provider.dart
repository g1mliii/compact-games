import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/locale_provider.dart';
import '../../services/tray_service.dart';
import '../compression/compression_progress_provider.dart';
import '../compression/compression_state.dart';
import '../settings/settings_provider.dart';
import 'auto_compression_status_provider.dart';

@visibleForTesting
TrayStatusMode deriveTrayStatusMode({
  required String? gameName,
  required CompressionJobStatus? jobStatus,
  required bool autoRunning,
  required bool autoRunningHasError,
}) {
  if (gameName != null &&
      (jobStatus == CompressionJobStatus.running ||
          jobStatus == CompressionJobStatus.pending)) {
    return TrayStatusMode.compressing;
  }
  if (autoRunningHasError) {
    return TrayStatusMode.error;
  }
  if (!autoRunning) {
    return TrayStatusMode.paused;
  }
  return TrayStatusMode.idle;
}

/// Effect provider that watches compression and automation state, then pushes
/// derived TrayStatus to TrayService. No owned state — pure side-effect.
///
/// Uses .select() on each watched field to avoid rebuilds from unrelated
/// settings changes (mirrors automationSettingsSyncProvider pattern).
final trayStatusSyncProvider = Provider<void>((ref) {
  final gameName = ref.watch(compressingGameNameProvider);

  final jobStatus = ref.watch(
    activeCompressionJobProvider.select((j) => j?.status),
  );

  final autoRunningState = ref.watch(
    autoCompressionRunningProvider.select(
      (a) => (running: a.valueOrNull ?? false, hasError: a.hasError),
    ),
  );
  final autoRunning = autoRunningState.running;
  final autoRunningHasError = autoRunningState.hasError;

  final minimizeToTray = ref.watch(
    settingsProvider.select(
      (s) => s.valueOrNull?.settings.minimizeToTray ?? true,
    ),
  );
  final autoCompressionEnabled = ref.watch(
    settingsProvider.select(
      (s) => s.valueOrNull?.settings.autoCompress ?? false,
    ),
  );
  final l10n = ref.watch(appLocalizationsProvider);

  // Reuse the shared bucketed activity model so the tray does not react
  // more often than the visible compression/decompression UI.
  final progressPercent = ref.watch(
    activeCompressionUiModelProvider.select((activity) {
      if (activity == null || !activity.hasKnownFileTotal) {
        return null;
      }
      return activity.percent;
    }),
  );

  final mode = deriveTrayStatusMode(
    gameName: gameName,
    jobStatus: jobStatus,
    autoRunning: autoRunning,
    autoRunningHasError: autoRunningHasError,
  );

  // Push to singleton. Pre-init updates are queued and applied during init.
  final trayService = TrayService.instance;
  final owner = ref.container;
  ref.onDispose(() {
    trayService.unregisterAutoCompressionToggle(owner);
  });
  trayService.registerAutoCompressionToggle(
    owner: owner,
    setEnabled: (enabled) async {
      ref.read(settingsProvider.notifier).setAutoCompress(enabled);
    },
  );
  trayService.minimizeToTray = minimizeToTray;
  trayService.update(
    TrayStatus(
      mode: mode,
      activeGameName: gameName,
      progressPercent: progressPercent,
      autoCompressionEnabled: autoCompressionEnabled,
      strings: TrayStrings(
        openAppLabel: l10n.trayOpenApp,
        pauseAutoCompressionLabel: l10n.trayPauseAutoCompression,
        resumeAutoCompressionLabel: l10n.trayResumeAutoCompression,
        quitLabel: l10n.commonQuit,
        compressingLabel: l10n.trayCompressing,
        pausedStatusLabel: l10n.trayPaused,
        errorStatusLabel: l10n.trayError,
      ),
    ),
  );
});
