import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../services/tray_service.dart';
import '../../src/rust/api/update.dart' as rust_update;
import '../compression/compression_provider.dart';
import '../games/game_list_provider.dart';
import '../settings/settings_provider.dart';

enum UpdateStatus { idle, checking, available, downloading, downloaded, error }

@immutable
class UpdateState {
  final UpdateStatus status;
  final rust_update.UpdateCheckResult? info;
  final String? error;
  final String? installerPath;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.error,
    this.installerPath,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    rust_update.UpdateCheckResult? Function()? info,
    String? Function()? error,
    String? Function()? installerPath,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info != null ? info() : this.info,
      error: error != null ? error() : this.error,
      installerPath: installerPath != null
          ? installerPath()
          : this.installerPath,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UpdateState) return false;
    return status == other.status &&
        info == other.info &&
        error == other.error &&
        installerPath == other.installerPath;
  }

  @override
  int get hashCode => Object.hash(status, info, error, installerPath);
}

final updateProvider = AsyncNotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

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

class UpdateNotifier extends AsyncNotifier<UpdateState> {
  @override
  Future<UpdateState> build() async {
    return const UpdateState();
  }

  Future<void> checkForUpdate() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.status == UpdateStatus.checking ||
        current.status == UpdateStatus.downloading) {
      return;
    }

    state = AsyncValue.data(
      current.copyWith(status: UpdateStatus.checking, error: () => null),
    );

    try {
      final result = await ref
          .read(rustBridgeServiceProvider)
          .checkForUpdate(currentVersion: AppConstants.appVersion);

      // Re-read state after the await to avoid clobbering concurrent changes.
      final post = state.valueOrNull ?? current;
      if (result.updateAvailable) {
        state = AsyncValue.data(
          post.copyWith(status: UpdateStatus.available, info: () => result),
        );
      } else {
        state = AsyncValue.data(post.copyWith(status: UpdateStatus.idle));
      }
    } catch (e) {
      state = AsyncValue.data(
        (state.valueOrNull ?? current).copyWith(
          status: UpdateStatus.error,
          error: () => e.toString(),
        ),
      );
    }
  }

  Future<void> downloadUpdate() async {
    final current = state.valueOrNull;
    if (current == null || current.info == null) return;
    if (current.status == UpdateStatus.downloading) return;

    final info = current.info!;
    state = AsyncValue.data(
      current.copyWith(status: UpdateStatus.downloading, error: () => null),
    );

    try {
      final appData = await getApplicationSupportDirectory();
      final updateDir = Directory('${appData.path}/updates');
      final fileName = 'CompactGames-Setup-${info.latestVersion}.exe';
      final destPath = '${updateDir.path}/$fileName';

      final resultPath = await ref
          .read(rustBridgeServiceProvider)
          .downloadUpdate(
            url: info.downloadUrl,
            destPath: destPath,
            expectedSha256: info.checksumSha256,
          );

      // Re-read state after the await to avoid clobbering concurrent changes.
      state = AsyncValue.data(
        (state.valueOrNull ?? current).copyWith(
          status: UpdateStatus.downloaded,
          installerPath: () => resultPath,
        ),
      );
    } catch (e) {
      state = AsyncValue.data(
        (state.valueOrNull ?? current).copyWith(
          status: UpdateStatus.error,
          error: () => e.toString(),
        ),
      );
    }
  }

  Future<void> launchInstaller() async {
    final current = state.valueOrNull;
    if (current == null || current.installerPath == null) return;

    // Don't install while compression is active.
    final compressionState = ref.read(compressionProvider);
    if (compressionState.hasActiveJob) return;

    final installerPath = current.installerPath!;
    await ref.read(installerLauncherProvider)(installerPath);
    await ref.read(settingsProvider.notifier).flush();
    await ref.read(updateExitRequestProvider)();
  }
}
