part of 'rust_bridge_service.dart';

// ── Game & compression mappers ──────────────────────────────────────

GameInfo _mapFrbGameInfo(rust_types.FrbGameInfo frb) {
  return GameInfo(
    name: frb.name,
    path: frb.path,
    platform: _mapFrbPlatform(frb.platform),
    sizeBytes: frb.sizeBytes.toInt(),
    compressedSize: frb.compressedSize?.toInt(),
    isCompressed: frb.isCompressed,
    isDirectStorage: frb.isDirectstorage,
    excluded: frb.excluded,
    lastPlayed: frb.lastPlayed != null
        ? DateTime.fromMillisecondsSinceEpoch(frb.lastPlayed!.toInt())
        : null,
  );
}

Platform _mapFrbPlatform(rust_types.FrbPlatform frb) {
  return switch (frb) {
    rust_types.FrbPlatform.steam => Platform.steam,
    rust_types.FrbPlatform.epicGames => Platform.epicGames,
    rust_types.FrbPlatform.gogGalaxy => Platform.gogGalaxy,
    rust_types.FrbPlatform.ubisoftConnect => Platform.ubisoftConnect,
    rust_types.FrbPlatform.eaApp => Platform.eaApp,
    rust_types.FrbPlatform.battleNet => Platform.battleNet,
    rust_types.FrbPlatform.xboxGamePass => Platform.xboxGamePass,
    rust_types.FrbPlatform.custom => Platform.custom,
  };
}

CompressionProgress _mapFrbProgress(rust_types.FrbCompressionProgress frb) {
  return CompressionProgress(
    gameName: frb.gameName,
    filesTotal: frb.filesTotal.toInt(),
    filesProcessed: frb.filesProcessed.toInt(),
    bytesOriginal: frb.bytesOriginal.toInt(),
    bytesCompressed: frb.bytesCompressed.toInt(),
    bytesSaved: frb.bytesSaved.toInt(),
    estimatedTimeRemaining: frb.estimatedTimeRemainingMs != null
        ? Duration(milliseconds: frb.estimatedTimeRemainingMs!.toInt())
        : null,
    isComplete: frb.isComplete,
  );
}

CompressionEstimate _mapFrbEstimate(rust_types.FrbCompressionEstimate frb) {
  return CompressionEstimate(
    scannedFiles: frb.scannedFiles.toInt(),
    sampledBytes: frb.sampledBytes.toInt(),
    estimatedCompressedBytes: frb.estimatedCompressedBytes.toInt(),
    estimatedSavedBytes: frb.estimatedSavedBytes.toInt(),
    estimatedSavingsRatio: frb.estimatedSavingsRatio,
    artworkCandidatePath: frb.artworkCandidatePath,
    executableCandidatePath: frb.executableCandidatePath,
  );
}

// ignore: unused_element
CompressionStats _mapFrbStats(rust_types.FrbCompressionStats frb) {
  return CompressionStats(
    originalBytes: frb.originalBytes.toInt(),
    compressedBytes: frb.compressedBytes.toInt(),
    filesProcessed: frb.filesProcessed.toInt(),
    filesSkipped: frb.filesSkipped.toInt(),
    durationMs: frb.durationMs.toInt(),
  );
}

// ── Conversion helpers (Dart → FRB) ────────────────────────────────

rust_types.FrbCompressionAlgorithm _toFrbAlgorithm(CompressionAlgorithm algo) {
  return switch (algo) {
    CompressionAlgorithm.xpress4k =>
      rust_types.FrbCompressionAlgorithm.xpress4K,
    CompressionAlgorithm.xpress8k =>
      rust_types.FrbCompressionAlgorithm.xpress8K,
    CompressionAlgorithm.xpress16k =>
      rust_types.FrbCompressionAlgorithm.xpress16K,
    CompressionAlgorithm.lzx => rust_types.FrbCompressionAlgorithm.lzx,
  };
}

rust_types.FrbPlatform _toFrbPlatform(Platform platform) {
  return switch (platform) {
    Platform.steam => rust_types.FrbPlatform.steam,
    Platform.epicGames => rust_types.FrbPlatform.epicGames,
    Platform.gogGalaxy => rust_types.FrbPlatform.gogGalaxy,
    Platform.ubisoftConnect => rust_types.FrbPlatform.ubisoftConnect,
    Platform.eaApp => rust_types.FrbPlatform.eaApp,
    Platform.battleNet => rust_types.FrbPlatform.battleNet,
    Platform.xboxGamePass => rust_types.FrbPlatform.xboxGamePass,
    Platform.custom => rust_types.FrbPlatform.custom,
  };
}

// ── Automation mappers ──────────────────────────────────────────────

WatcherEvent _mapFrbWatcherEvent(rust_types.FrbWatcherEvent frb) {
  return switch (frb) {
    rust_types.FrbWatcherEvent_GameInstalled(:final path, :final gameName) =>
      WatcherEvent(
        type: WatcherEventType.installed,
        gamePath: path,
        gameName: gameName,
        timestamp: DateTime.now(),
      ),
    rust_types.FrbWatcherEvent_GameModified(:final path, :final gameName) =>
      WatcherEvent(
        type: WatcherEventType.modified,
        gamePath: path,
        gameName: gameName,
        timestamp: DateTime.now(),
      ),
    rust_types.FrbWatcherEvent_GameUninstalled(:final path, :final gameName) =>
      WatcherEvent(
        type: WatcherEventType.uninstalled,
        gamePath: path,
        gameName: gameName,
        timestamp: DateTime.now(),
      ),
  };
}

AutomationJob _mapFrbAutomationJob(rust_types.FrbAutomationJob frb) {
  return AutomationJob(
    gamePath: frb.gamePath,
    gameName: frb.gameName,
    kind: _mapFrbJobKind(frb.kind),
    status: _mapFrbJobStatus(frb.status),
    queuedAt: DateTime.fromMillisecondsSinceEpoch(frb.queuedAtMs.toInt()),
    startedAt: frb.startedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(frb.startedAtMs!.toInt())
        : null,
    error: frb.error,
  );
}

AutomationJobKind _mapFrbJobKind(rust_types.FrbAutomationJobKind frb) {
  return switch (frb) {
    rust_types.FrbAutomationJobKind.newInstall => AutomationJobKind.newInstall,
    rust_types.FrbAutomationJobKind.reconcile => AutomationJobKind.reconcile,
    rust_types.FrbAutomationJobKind.opportunistic =>
      AutomationJobKind.opportunistic,
  };
}

AutomationJobStatus _mapFrbJobStatus(rust_types.FrbAutomationJobStatus frb) {
  return switch (frb) {
    rust_types.FrbAutomationJobStatus.pending => AutomationJobStatus.pending,
    rust_types.FrbAutomationJobStatus.waitingForSettle =>
      AutomationJobStatus.waitingForSettle,
    rust_types.FrbAutomationJobStatus.waitingForIdle =>
      AutomationJobStatus.waitingForIdle,
    rust_types.FrbAutomationJobStatus.compressing =>
      AutomationJobStatus.compressing,
    rust_types.FrbAutomationJobStatus.completed =>
      AutomationJobStatus.completed,
    rust_types.FrbAutomationJobStatus.failed => AutomationJobStatus.failed,
    rust_types.FrbAutomationJobStatus.skipped => AutomationJobStatus.skipped,
  };
}

SchedulerState _mapFrbSchedulerState(rust_types.FrbSchedulerState frb) {
  return switch (frb) {
    rust_types.FrbSchedulerState.idle => SchedulerState.idle,
    rust_types.FrbSchedulerState.settling => SchedulerState.settling,
    rust_types.FrbSchedulerState.waitingForIdle =>
      SchedulerState.waitingForIdle,
    rust_types.FrbSchedulerState.safetyCheck => SchedulerState.safetyCheck,
    rust_types.FrbSchedulerState.compressing => SchedulerState.compressing,
    rust_types.FrbSchedulerState.paused => SchedulerState.paused,
    rust_types.FrbSchedulerState.backoff => SchedulerState.backoff,
  };
}
