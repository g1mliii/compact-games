import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'tray_service.dart';

abstract interface class StartupWindowAdapter {
  Future<void> ensureInitialized();
  void addListener(WindowListener listener);
  void removeListener(WindowListener listener);
  Future<void> setPreventClose(bool value);
  Future<void> waitUntilReadyToShow(
    WindowOptions options,
    Future<void> Function() callback,
  );
  Future<void> showInactive();
}

abstract interface class StartupTrayAdapter {
  Future<void> init();
}

Future<void> initializeStartupWindow({
  required StartupWindowAdapter window,
  required StartupTrayAdapter tray,
  required WindowListener listener,
  required WindowOptions options,
  required bool isWeb,
  required TargetPlatform targetPlatform,
  void Function(Object error)? onTrayInitError,
}) async {
  await window.ensureInitialized();
  window.removeListener(listener);
  window.addListener(listener);

  if (!isWeb && targetPlatform == TargetPlatform.windows) {
    await window.setPreventClose(true);
  }

  await window.waitUntilReadyToShow(options, () async {
    await window.showInactive();
    try {
      await tray.init();
    } catch (error) {
      onTrayInitError?.call(error);
    }
  });
}

class WindowManagerStartupAdapter implements StartupWindowAdapter {
  const WindowManagerStartupAdapter();

  @override
  Future<void> ensureInitialized() => windowManager.ensureInitialized();

  @override
  void addListener(WindowListener listener) {
    windowManager.addListener(listener);
  }

  @override
  void removeListener(WindowListener listener) {
    windowManager.removeListener(listener);
  }

  @override
  Future<void> setPreventClose(bool value) {
    return windowManager.setPreventClose(value);
  }

  @override
  Future<void> waitUntilReadyToShow(
    WindowOptions options,
    Future<void> Function() callback,
  ) {
    return windowManager.waitUntilReadyToShow(options, () {
      callback();
    });
  }

  @override
  Future<void> showInactive() {
    return windowManager.show(inactive: true);
  }
}

class TrayStartupAdapter implements StartupTrayAdapter {
  const TrayStartupAdapter(this._trayService);

  final TrayService _trayService;

  @override
  Future<void> init() {
    return _trayService.init();
  }
}
