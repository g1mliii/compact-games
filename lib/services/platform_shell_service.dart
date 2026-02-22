import 'dart:io';

/// Minimal shell integration for opening folders from UI actions.
class PlatformShellService {
  const PlatformShellService();

  Future<bool> openFolder(String path) async {
    if (path.trim().isEmpty) {
      return false;
    }
    if (!Platform.isWindows) {
      return false;
    }

    final result = await Process.run('explorer.exe', [path], runInShell: true);
    return result.exitCode == 0;
  }
}
