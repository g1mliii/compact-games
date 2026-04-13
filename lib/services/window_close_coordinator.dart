import 'dart:ui';

import '../core/performance/ui_memory_lifecycle.dart';

abstract interface class TrayLifecycleAdapter {
  bool get quitRequested;
  bool get minimizeToTray;
  bool get isInitialized;
  Future<void> dispose();
}

abstract interface class WindowLifecycleAdapter {
  Future<void> hide();
  Future<void> setPreventClose(bool value);
  Future<void> destroy();
  Future<void> close();
}

abstract interface class AppShutdownAdapter {
  Future<void> shutdownApp();
}

typedef MemoryTrimHandler = void Function(UiMemoryTrimLevel level);
typedef LifecycleHooksCleanup = void Function();
typedef AppExitRequest = Future<void> Function();

/// Coordinates close/minimize behavior for desktop lifecycle events.
class WindowCloseCoordinator {
  WindowCloseCoordinator({
    required TrayLifecycleAdapter tray,
    required WindowLifecycleAdapter window,
    required AppShutdownAdapter appShutdown,
    required MemoryTrimHandler trimMemory,
    required LifecycleHooksCleanup cleanupLifecycleHooks,
    required AppExitRequest requestAppExit,
    required VoidCallback onHiddenToTray,
  }) : _tray = tray,
       _window = window,
       _appShutdown = appShutdown,
       _trimMemory = trimMemory,
       _cleanupLifecycleHooks = cleanupLifecycleHooks,
       _requestAppExit = requestAppExit,
       _onHiddenToTray = onHiddenToTray;

  final TrayLifecycleAdapter _tray;
  final WindowLifecycleAdapter _window;
  final AppShutdownAdapter _appShutdown;
  final MemoryTrimHandler _trimMemory;
  final LifecycleHooksCleanup _cleanupLifecycleHooks;
  final AppExitRequest _requestAppExit;
  final VoidCallback _onHiddenToTray;

  bool _isClosing = false;

  Future<void> onWindowClose() async {
    if (_isClosing) return;

    if (!_tray.quitRequested && _tray.minimizeToTray && _tray.isInitialized) {
      var hidden = false;
      try {
        await _window.hide();
        hidden = true;
      } catch (_) {}
      if (hidden) {
        _onHiddenToTray();
        _trimMemory(UiMemoryTrimLevel.trayHide);
        return;
      }
    }

    _isClosing = true;
    await _shutdownAndClose();
  }

  void onWindowMinimize() {
    _trimMemory(UiMemoryTrimLevel.background);
  }

  Future<void> _shutdownAndClose() async {
    try {
      await _appShutdown.shutdownApp();
    } finally {
      try {
        await _tray.dispose();
      } catch (_) {}
      _trimMemory(UiMemoryTrimLevel.shutdown);
      try {
        await _window.setPreventClose(false);
      } catch (_) {
        // Best effort: close interception may already be unavailable.
      }
      try {
        await _window.destroy();
        _cleanupLifecycleHooks();
        return;
      } catch (_) {
        // Best effort fallback.
      }
      try {
        await _window.close();
        _cleanupLifecycleHooks();
        return;
      } catch (_) {
        // Try platform-level app close if window close fails.
      }

      try {
        await _requestAppExit();
        _cleanupLifecycleHooks();
        return;
      } catch (_) {
        // Best effort: if app is still alive, allow another close attempt.
      }
      _isClosing = false;
    }
  }
}
