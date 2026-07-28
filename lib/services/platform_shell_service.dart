import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../models/game_info.dart';
import 'game_launch_target_store.dart';

enum GameLaunchResult { requested, selectionCancelled, targetNotFound, failed }

/// Thrown when the native path picker could not be shown at all, so a null
/// selection must not be mistaken for the user cancelling the dialog.
class PathPickerUnavailableException implements Exception {
  const PathPickerUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'PathPickerUnavailableException: $reason';
}

/// Minimal Windows shell integration for game-library UI actions.
class PlatformShellService {
  const PlatformShellService({
    GameLaunchTargetStore launchTargetStore = const GameLaunchTargetStore(),
  }) : _launchTargetStore = launchTargetStore;

  final GameLaunchTargetStore _launchTargetStore;

  Future<bool> openFolder(String path) async {
    if (path.trim().isEmpty) {
      return false;
    }
    if (!io.Platform.isWindows) {
      return false;
    }

    final result = await io.Process.run('explorer.exe', [path]);
    return result.exitCode == 0;
  }

  Future<GameLaunchResult> launchGame(GameInfo game) async {
    try {
      final steamAppId = game.steamAppId;
      if (game.platform == Platform.steam &&
          steamAppId != null &&
          steamAppId > 0) {
        return _resultFor(await launchUri('steam://rungameid/$steamAppId'));
      }

      // The game itself may already be an executable rather than a folder.
      final direct = await _usableExecutable(game.path);
      if (direct != null) {
        return _resultFor(await launchExecutable(direct));
      }

      final stored = await _launchTargetStore.read(game.path);
      var target = await _usableExecutable(stored);
      if (stored != null && target == null) {
        await _launchTargetStore.remove(game.path);
      }
      if (target == null) {
        // A folder can contain several valid executables (including launchers
        // and tools), so only use a target the user selected explicitly.
        final picked = await pickGameExecutable();
        if (picked == null) {
          return GameLaunchResult.selectionCancelled;
        }
        target = await _usableExecutable(picked);
        if (target == null) {
          return GameLaunchResult.targetNotFound;
        }
      }

      await _launchTargetStore.write(game.path, target);
      return _resultFor(await launchExecutable(target));
    } catch (_) {
      return GameLaunchResult.failed;
    }
  }

  static GameLaunchResult _resultFor(bool requested) =>
      requested ? GameLaunchResult.requested : GameLaunchResult.failed;

  /// Normalized form of [path] when it names a launchable file that exists,
  /// otherwise null. The extension check runs first so unlaunchable candidates
  /// never cost a filesystem stat.
  Future<String?> _usableExecutable(String? path) async {
    if (path == null) {
      return null;
    }
    final normalized = _normalizedExecutablePath(path);
    if (normalized == null || !await io.File(normalized).exists()) {
      return null;
    }
    return normalized;
  }

  Future<bool> launchUri(String uri) async {
    if (uri.trim().isEmpty || !io.Platform.isWindows) {
      return false;
    }

    try {
      await io.Process.start('explorer.exe', [
        uri,
      ], mode: io.ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> launchExecutable(String executablePath) async {
    final trimmedPath = executablePath.trim();
    if (trimmedPath.isEmpty || !io.Platform.isWindows) {
      return false;
    }
    if (!await io.File(trimmedPath).exists()) {
      return false;
    }

    // Shortcuts, batch files, and internet shortcuts are not executable
    // images, so `Process.start` cannot run them directly — hand them to the
    // shell the same way the rest of this service does.
    if (p.extension(trimmedPath).toLowerCase() != '.exe') {
      return launchUri(trimmedPath);
    }

    try {
      await io.Process.start(
        trimmedPath,
        const <String>[],
        workingDirectory: p.dirname(trimmedPath),
        mode: io.ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Extensions the picker is allowed to return and that [launchExecutable]
  /// knows how to start. Anything the dialog's "All Files" filter lets the
  /// user choose but that is not listed here would be rejected after the
  /// fact, leaving them no way to proceed.
  static const _launchableExtensions = <String>{
    '.exe',
    '.bat',
    '.cmd',
    '.lnk',
    '.url',
  };

  String? _normalizedExecutablePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty ||
        !_launchableExtensions.contains(p.extension(trimmed).toLowerCase())) {
      return null;
    }
    return p.normalize(trimmed);
  }

  Future<String?> pickGameFolder() async {
    if (!io.Platform.isWindows) {
      throw const PathPickerUnavailableException('unsupported platform');
    }
    return _showWindowsPathPicker(pickExecutable: false);
  }

  Future<String?> pickGameExecutable() async {
    if (!io.Platform.isWindows) {
      throw const PathPickerUnavailableException('unsupported platform');
    }
    return _showWindowsPathPicker(pickExecutable: true);
  }

  Future<String?> _showWindowsPathPicker({required bool pickExecutable}) async {
    final script = pickExecutable
        ? '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = 'Select game executable'
\$dialog.Filter = "Game Launchers (*.exe;*.bat;*.cmd;*.lnk;*.url)|*.exe;*.bat;*.cmd;*.lnk;*.url|Executable Files (*.exe)|*.exe"
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$dialog.FileName }
'''
        : '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = 'Select game folder'
\$dialog.Filter = "Folders|*.folder"
\$dialog.Multiselect = \$false
\$dialog.CheckFileExists = \$false
\$dialog.CheckPathExists = \$true
\$dialog.ValidateNames = \$false
\$dialog.FileName = "Select folder"
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  \$selected = [System.IO.Path]::GetDirectoryName(\$dialog.FileName)
  if (\$selected) { Write-Output \$selected }
}
''';

    final io.ProcessResult result;
    try {
      result = await io.Process.run('powershell.exe', <String>[
        '-NoLogo',
        '-NonInteractive',
        '-NoProfile',
        '-STA',
        '-Command',
        script,
      ]);
    } catch (error) {
      // PowerShell blocked by policy, missing, or otherwise unrunnable. This
      // is not the user declining the dialog, so callers must be able to tell
      // the two apart instead of silently doing nothing.
      throw PathPickerUnavailableException('powershell.exe failed: $error');
    }
    if (result.exitCode != 0) {
      throw PathPickerUnavailableException(
        'powershell.exe exited with ${result.exitCode}',
      );
    }

    // No output means the user closed the dialog without choosing anything.
    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      return null;
    }
    final lines = output
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return null;
    }
    return lines.last;
  }
}
