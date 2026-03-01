part of 'tray_service.dart';

abstract interface class TrayPlatformAdapter {
  void addListener(TrayListener listener);
  void removeListener(TrayListener listener);
  Future<void> setIcon(String iconPath);
  Future<void> setToolTip(String tooltip);
  Future<void> setContextMenu(Menu menu);
  Future<void> popUpContextMenu();
  Future<void> destroy();
}

class _DefaultTrayPlatformAdapter implements TrayPlatformAdapter {
  const _DefaultTrayPlatformAdapter();

  @override
  void addListener(TrayListener listener) => trayManager.addListener(listener);

  @override
  void removeListener(TrayListener listener) =>
      trayManager.removeListener(listener);

  @override
  Future<void> setIcon(String iconPath) => trayManager.setIcon(iconPath);

  @override
  Future<void> setToolTip(String tooltip) => trayManager.setToolTip(tooltip);

  @override
  Future<void> setContextMenu(Menu menu) => trayManager.setContextMenu(menu);

  @override
  Future<void> popUpContextMenu() => trayManager.popUpContextMenu();

  @override
  Future<void> destroy() => trayManager.destroy();
}

abstract interface class WindowPlatformAdapter {
  Future<void> show();
  Future<void> focus();
  Future<void> close();
}

class _DefaultWindowPlatformAdapter implements WindowPlatformAdapter {
  const _DefaultWindowPlatformAdapter();

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> close() => windowManager.close();
}
