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

    final result = await Process.run('explorer.exe', [path]);
    return result.exitCode == 0;
  }

  Future<String?> pickGameFolder() async {
    if (!Platform.isWindows) {
      return null;
    }
    return _showWindowsPathPicker(
      description: 'Select game folder',
      pickExecutable: false,
    );
  }

  Future<String?> pickGameExecutable() async {
    if (!Platform.isWindows) {
      return null;
    }
    return _showWindowsPathPicker(
      description: 'Select game executable',
      pickExecutable: true,
    );
  }

  Future<String?> _showWindowsPathPicker({
    required String description,
    required bool pickExecutable,
  }) async {
    final script = pickExecutable
        ? '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = "$description"
\$dialog.Filter = "Executable Files (*.exe)|*.exe|All Files (*.*)|*.*"
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$dialog.FileName }
'''
        : '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
\$dialog.Description = "$description"
\$dialog.ShowNewFolderButton = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$dialog.SelectedPath }
''';

    try {
      final result = await Process.run('powershell.exe', <String>[
        '-NoLogo',
        '-NonInteractive',
        '-NoProfile',
        '-STA',
        '-Command',
        script,
      ]);
      if (result.exitCode != 0) {
        return null;
      }
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
    } catch (_) {
      return null;
    }
  }
}
