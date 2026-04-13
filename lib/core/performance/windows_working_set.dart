import 'dart:ffi';
import 'dart:io';

typedef _GetCurrentProcessNative = IntPtr Function();
typedef _GetCurrentProcessDart = int Function();
typedef _SetProcessWorkingSetSizeNative =
    Int32 Function(IntPtr process, IntPtr minimumSize, IntPtr maximumSize);
typedef _SetProcessWorkingSetSizeDart =
    int Function(int process, int minimumSize, int maximumSize);

/// Best-effort resident-memory trim for Windows tray mode.
abstract final class WindowsWorkingSet {
  static _GetCurrentProcessDart? _getCurrentProcess;
  static _SetProcessWorkingSetSizeDart? _setProcessWorkingSetSize;
  static bool _resolveAttempted = false;

  static bool trimCurrentProcess() {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      _resolve();
      final getCurrentProcess = _getCurrentProcess;
      final setProcessWorkingSetSize = _setProcessWorkingSetSize;
      if (getCurrentProcess == null || setProcessWorkingSetSize == null) {
        return false;
      }

      final process = getCurrentProcess();
      return setProcessWorkingSetSize(process, -1, -1) != 0;
    } catch (_) {
      return false;
    }
  }

  static void _resolve() {
    if (_resolveAttempted) {
      return;
    }
    _resolveAttempted = true;

    final kernel32 = DynamicLibrary.open('kernel32.dll');
    _getCurrentProcess = kernel32
        .lookupFunction<_GetCurrentProcessNative, _GetCurrentProcessDart>(
          'GetCurrentProcess',
        );
    _setProcessWorkingSetSize = kernel32
        .lookupFunction<
          _SetProcessWorkingSetSizeNative,
          _SetProcessWorkingSetSizeDart
        >('SetProcessWorkingSetSize');
  }
}
