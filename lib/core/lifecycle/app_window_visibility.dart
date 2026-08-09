import 'package:flutter/foundation.dart';

enum AppWindowVisibility { visible, hiddenToTray }

/// Process-wide window visibility signal used by platform lifecycle callbacks.
///
/// This intentionally lives outside Riverpod because window close/tray callbacks
/// are owned by platform singletons that are initialized before the root
/// [ProviderScope] exists.
class AppWindowVisibilityController extends ChangeNotifier {
  AppWindowVisibility _state = AppWindowVisibility.visible;

  AppWindowVisibility get state => _state;

  bool get isHiddenToTray => _state == AppWindowVisibility.hiddenToTray;

  void markHiddenToTray() {
    _setState(AppWindowVisibility.hiddenToTray);
  }

  void markVisible() {
    _setState(AppWindowVisibility.visible);
  }

  void _setState(AppWindowVisibility next) {
    if (_state == next) {
      return;
    }
    _state = next;
    notifyListeners();
  }
}

final AppWindowVisibilityController appWindowVisibilityController =
    AppWindowVisibilityController();

/// Restores visible-only UI resources after a genuine foreground resume.
///
/// Windows briefly reports the Flutter app as resumed when the native tray
/// context menu takes foreground ownership, even though the app window remains
/// hidden. Treat the explicit window visibility state as authoritative so that
/// opening the tray menu cannot remount the hidden UI or suppress its delayed
/// working-set trim.
void handleAppLifecycleResumed({
  required AppWindowVisibilityController visibilityController,
  required VoidCallback configureVisibleUi,
}) {
  if (visibilityController.isHiddenToTray) {
    return;
  }
  configureVisibleUi();
}
