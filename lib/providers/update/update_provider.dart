import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../services/tray_service.dart';
import '../../services/update_installer_cache.dart';
import '../../src/rust/api/update.dart' as rust_update;
import '../compression/compression_provider.dart';
import '../games/game_list_provider.dart';
import '../settings/settings_provider.dart';

/// [idle] means "not checked yet this session"; [upToDate] means "checked, and
/// this is the latest version". Keeping them apart is what lets the About
/// section confirm a check that found nothing instead of silently returning to
/// its starting state.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  downloaded,
  error,
}

/// True when a new update check may start.
///
/// Only an in-flight check or download blocks one. `available`, `downloaded`
/// and `error` must stay re-checkable: a release can be pulled and re-published
/// with corrected metadata, and this app is expected to sit in the tray for
/// days without a restart.
bool canStartUpdateCheck(UpdateState state) {
  return state.status != UpdateStatus.checking &&
      state.status != UpdateStatus.downloading;
}

/// True when the automatic interval check may run.
///
/// One restriction on top of [canStartUpdateCheck]: a verified installer that
/// is only waiting to be launched is never disturbed by a background check.
bool canStartAutomaticUpdateCheck(UpdateState state) {
  return canStartUpdateCheck(state) && state.status != UpdateStatus.downloaded;
}

@immutable
class UpdateState {
  final UpdateStatus status;
  final rust_update.UpdateCheckResult? info;
  final String? error;
  final String? installerPath;

  /// Which operation produced [error]. Recorded explicitly because [info]
  /// cannot stand in for it: a release found by an earlier check stays in
  /// state, so a later failed *check* would otherwise look like a failed
  /// download and be offered a retry-download button.
  final bool errorFromDownload;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.error,
    this.installerPath,
    this.errorFromDownload = false,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    rust_update.UpdateCheckResult? Function()? info,
    String? Function()? error,
    String? Function()? installerPath,
    bool? errorFromDownload,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info != null ? info() : this.info,
      error: error != null ? error() : this.error,
      installerPath: installerPath != null
          ? installerPath()
          : this.installerPath,
      errorFromDownload: errorFromDownload ?? this.errorFromDownload,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UpdateState) return false;
    return status == other.status &&
        info == other.info &&
        error == other.error &&
        installerPath == other.installerPath &&
        errorFromDownload == other.errorFromDownload;
  }

  @override
  int get hashCode =>
      Object.hash(status, info, error, installerPath, errorFromDownload);
}

final updateProvider = AsyncNotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

/// Kept injectable so distribution-specific behavior can be regression tested
/// without requiring a separate compiler invocation.
final selfUpdatesEnabledProvider = Provider<bool>((ref) {
  return AppConstants.selfUpdatesEnabled;
});

typedef InstallerLauncher = Future<void> Function(String installerPath);
typedef UpdateExitRequest = Future<void> Function();

final installerLauncherProvider = Provider<InstallerLauncher>((ref) {
  return (installerPath) async {
    await Process.start(installerPath, const [
      '/SILENT',
    ], mode: ProcessStartMode.detached);
  };
});

final updateExitRequestProvider = Provider<UpdateExitRequest>((ref) {
  return TrayService.instance.requestQuit;
});

final updateInstallerCacheProvider = Provider<UpdateInstallerCache>((ref) {
  return UpdateInstallerCache();
});

class UpdateNotifier extends AsyncNotifier<UpdateState> {
  /// A fast update check can resolve inside a single frame. Without a floor the
  /// spinner would never become visible and the button would look inert.
  static const Duration _minimumVisibleCheck = Duration(milliseconds: 600);

  @override
  Future<UpdateState> build() async {
    return const UpdateState();
  }

  /// Set [automatic] for interval/background checks, which additionally leave a
  /// downloaded installer alone — see [canStartAutomaticUpdateCheck].
  Future<void> checkForUpdate({bool automatic = false}) async {
    if (!ref.read(selfUpdatesEnabledProvider)) return;

    final current = state.value;
    if (current == null) return;
    final admitted = automatic
        ? canStartAutomaticUpdateCheck(current)
        : canStartUpdateCheck(current);
    if (!admitted) {
      return;
    }

    state = AsyncValue.data(
      current.copyWith(status: UpdateStatus.checking, error: () => null),
    );

    // Monotonic on purpose: a wall clock can step backwards mid-check (DST,
    // NTP correction) and would turn the floor below into an unbounded sleep
    // that pins `checking` and locks out every later check.
    final elapsed = Stopwatch()..start();

    rust_update.UpdateCheckResult? result;
    String? failure;
    String? cachedInstaller;
    try {
      result = await ref
          .read(rustBridgeServiceProvider)
          .checkForUpdate(
            currentVersion: AppConstants.appVersion,
            // An explicit user action must be able to observe a release (or a
            // just-uploaded latest.json) that appeared inside Rust's six-hour
            // automatic-check cache window.
            forceRefresh: !automatic,
          );

      if (!result.manifestAvailable) {
        // Rust reports a missing latest.json as "not available" rather than
        // "up to date"; turning that into a positive claim would tell the user
        // they are current at the exact moment we could not find out.
        failure = 'Update manifest is unavailable';
        result = null;
      } else if (result.updateAvailable) {
        // A checksum-verified installer for the version that is still current
        // is adopted instead of being re-downloaded — the state itself does not
        // survive a restart, but the file does.
        cachedInstaller = await _findVerifiedInstaller(result.latestVersion);
      }
    } catch (e) {
      failure = e.toString();
    }

    // One floor for one terminal write, measured across every await above so a
    // slow path pays nothing extra. Only a person watching the spinner needs
    // it; a background check must not hold `checking` against a manual press.
    if (!automatic) {
      await _holdForMinimumVisibleCheck(elapsed);
    }

    // Re-read state after every await to avoid clobbering concurrent changes.
    final post = state.value ?? current;
    if (failure != null) {
      state = AsyncValue.data(
        post.copyWith(
          status: UpdateStatus.error,
          error: () => failure,
          errorFromDownload: false,
        ),
      );
      return;
    }

    final checkResult = result!;
    state = AsyncValue.data(
      checkResult.updateAvailable
          ? post.copyWith(
              status: cachedInstaller == null
                  ? UpdateStatus.available
                  : UpdateStatus.downloaded,
              info: () => checkResult,
              installerPath: () => cachedInstaller,
            )
          // `info` is cleared alongside the installer: keeping a release that is
          // no longer offered would later be mistaken for a downloadable one.
          : post.copyWith(
              status: UpdateStatus.upToDate,
              info: () => null,
              installerPath: () => null,
            ),
    );

    // Deliberately after the result: only now is it known which version is
    // current, and the installer for that version must survive the sweep.
    await _deleteStaleInstallers(
      keepVersion: checkResult.updateAvailable
          ? checkResult.latestVersion
          : null,
    );
  }

  /// Keeps `checking` on screen long enough to read. See [_minimumVisibleCheck].
  Future<void> _holdForMinimumVisibleCheck(Stopwatch elapsed) async {
    final remaining = _minimumVisibleCheck - elapsed.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> downloadUpdate() async {
    if (!ref.read(selfUpdatesEnabledProvider)) return;

    final current = state.value;
    if (current == null || current.info == null) return;
    if (current.status == UpdateStatus.downloading) return;

    final info = current.info!;
    state = AsyncValue.data(
      current.copyWith(status: UpdateStatus.downloading, error: () => null),
    );

    try {
      final destPath = await ref
          .read(updateInstallerCacheProvider)
          .installerPathFor(info.latestVersion);

      final resultPath = await ref
          .read(rustBridgeServiceProvider)
          .downloadUpdate(
            url: info.downloadUrl,
            destPath: destPath,
            expectedSha256: info.checksumSha256,
          );

      // The installer is verified on disk here, so it becomes available before
      // the best-effort sweep — a slow directory must never pin `downloading`.
      // Re-read state after the await to avoid clobbering concurrent changes.
      state = AsyncValue.data(
        (state.value ?? current).copyWith(
          status: UpdateStatus.downloaded,
          installerPath: () => resultPath,
        ),
      );

      await _deleteStaleInstallers(keepVersion: info.latestVersion);
    } catch (e) {
      state = AsyncValue.data(
        (state.value ?? current).copyWith(
          errorFromDownload: true,
          status: UpdateStatus.error,
          error: () => e.toString(),
        ),
      );
    }
  }

  Future<void> launchInstaller() async {
    if (!ref.read(selfUpdatesEnabledProvider)) return;

    final current = state.value;
    if (current == null || current.installerPath == null) return;

    // Don't install while compression is active.
    final compressionState = ref.read(compressionProvider);
    if (compressionState.hasActiveJob) return;

    final installerPath = current.installerPath!;
    // The silent installer is allowed to close this process. Finish app-owned
    // persistence before it starts so forced-close timing cannot race pending
    // settings writes (native compression/discovery state is persisted at the
    // operation boundary in Rust).
    await ref.read(settingsProvider.notifier).flush();
    await ref.read(installerLauncherProvider)(installerPath);
    await ref.read(updateExitRequestProvider)();
  }

  Future<String?> _findVerifiedInstaller(String version) async {
    try {
      return await ref
          .read(updateInstallerCacheProvider)
          .findVerifiedInstaller(version);
    } catch (error) {
      debugPrint('[update] Installer cache lookup failed: $error');
      return null;
    }
  }

  Future<void> _deleteStaleInstallers({String? keepVersion}) async {
    try {
      await ref
          .read(updateInstallerCacheProvider)
          .deleteStaleInstallers(keepVersion: keepVersion);
    } catch (error) {
      // Cache cleanup is best effort and must never block update checks or a
      // successfully verified installer from becoming available.
      debugPrint('[update] Installer cache cleanup failed: $error');
    }
  }
}
