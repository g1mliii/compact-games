import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'tray_service.dart';

final uninstallServiceProvider = Provider<UninstallService>((ref) {
  return UninstallService();
});

typedef UninstallerLauncher = Future<void> Function(String uninstallerPath);
typedef UninstallExitRequest = Future<void> Function();

class UninstallService {
  UninstallService({
    bool? isWindows,
    Directory Function()? appDirectoryResolver,
    UninstallerLauncher? launcher,
    UninstallExitRequest? exitRequest,
  }) : _isWindows =
           isWindows ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows),
       _appDirectoryResolver =
           appDirectoryResolver ?? _resolveInstalledAppDirectory,
       _launcher = launcher ?? _launchDetached,
       _exitRequest = exitRequest ?? TrayService.instance.requestQuit;

  final bool _isWindows;
  final Directory Function() _appDirectoryResolver;
  final UninstallerLauncher _launcher;
  final UninstallExitRequest _exitRequest;

  Future<bool> launch() async {
    if (!_isWindows) {
      return false;
    }
    final appDirectory = _appDirectoryResolver();
    final candidates =
        appDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .where(
              (file) => RegExp(
                r'^unins\d+\.exe$',
                caseSensitive: false,
              ).hasMatch(p.basename(file.path)),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    if (candidates.isEmpty) {
      return false;
    }
    await _launcher(candidates.first.path);
    // The uninstaller cannot remove the running executable or loaded native
    // libraries. Use the normal tray quit path so Rust and tray resources are
    // shut down cleanly instead of leaving Compact Games resident and causing
    // Inno Setup to report that the app is still in use.
    await _exitRequest();
    return true;
  }

  static Future<void> _launchDetached(String uninstallerPath) async {
    await Process.start(
      uninstallerPath,
      const <String>[],
      workingDirectory: p.dirname(uninstallerPath),
      mode: ProcessStartMode.detached,
    );
  }

  static Directory _resolveInstalledAppDirectory() {
    return Directory(p.dirname(Platform.resolvedExecutable));
  }
}
