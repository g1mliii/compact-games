import 'dart:io';

/// Manages the HKCU Run-key entry that mirrors the installer's `autostart`
/// task. The installer writes the same value under the same key; keeping them
/// aligned means the settings toggle and the install-time choice stay in sync.
class LaunchAtStartupService {
  const LaunchAtStartupService();

  static const String _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'Compact Games';

  Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    final result = await Process.run('reg.exe', [
      'query',
      _runKey,
      '/v',
      _valueName,
    ]);
    return result.exitCode == 0;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) return;
    if (enabled) {
      final exe = Platform.resolvedExecutable;
      final data = '"$exe" --minimized';
      final result = await Process.run('reg.exe', [
        'add',
        _runKey,
        '/v',
        _valueName,
        '/t',
        'REG_SZ',
        '/d',
        data,
        '/f',
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'reg.exe',
          const ['add'],
          result.stderr.toString(),
          result.exitCode,
        );
      }
    } else {
      final result = await Process.run('reg.exe', [
        'delete',
        _runKey,
        '/v',
        _valueName,
        '/f',
      ]);
      // exitCode 1 is "value not found" — treat as already-disabled.
      if (result.exitCode != 0 && result.exitCode != 1) {
        throw ProcessException(
          'reg.exe',
          const ['delete'],
          result.stderr.toString(),
          result.exitCode,
        );
      }
    }
  }
}
