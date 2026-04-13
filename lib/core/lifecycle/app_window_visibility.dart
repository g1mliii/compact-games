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
