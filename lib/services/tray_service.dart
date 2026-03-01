import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'tray_service_icon_cache.dart';
part 'tray_service_models.dart';
part 'tray_service_platform.dart';
part 'tray_service_presentation.dart';

/// Singleton system tray service.
///
/// All trayManager calls are wrapped in try/catch — tray failure is non-fatal.
/// Coalesces rapid status updates on a fixed tick to bound platform-call churn
/// without starving long-running progress updates.
class TrayService with TrayListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  TrayPlatformAdapter _trayPlatform = const _DefaultTrayPlatformAdapter();
  WindowPlatformAdapter _windowPlatform = const _DefaultWindowPlatformAdapter();

  bool _initialized = false;
  bool _disposed = false;
  bool _quitRequested = false;
  bool minimizeToTray = true;

  Duration _debounceDuration = const Duration(milliseconds: 400);
  Timer? _debounceTimer;
  TrayStatus _lastStatus = const TrayStatus(mode: TrayStatusMode.idle);
  TrayStatus? _pendingStatus;
  Future<void> _lifecycleQueue = Future<void>.value();
  Future<void> _updateQueue = Future<void>.value();
  Future<void> Function(bool enabled)? _setAutoCompressionEnabled;
  Object? _autoCompressionToggleOwner;
  bool _autoCompressionToggleInFlight = false;

  // Cached menu label to skip redundant setContextMenu platform calls.
  String _lastMenuSignature = '';
  String _lastTooltip = '';
  _TrayIconCache _iconCache = _TrayIconCache();

  bool get isInitialized => _initialized;
  bool get quitRequested => _quitRequested;

  /// Idempotent init. No-op if already initialized.
  Future<void> init() {
    return _enqueueLifecycle(() async {
      if (_initialized) return;

      _quitRequested = false;
      _lastStatus = const TrayStatus(mode: TrayStatusMode.idle);
      _autoCompressionToggleInFlight = false;
      _lastTooltip = '';

      try {
        final iconPath = await _iconCache.resolve();
        await _trayPlatform.setIcon(iconPath);
        await _trayPlatform.setToolTip('PressPlay');
        _lastTooltip = 'PressPlay';
        await _rebuildMenu(_lastStatus);
        _trayPlatform.addListener(this);
        _initialized = true;
        _disposed = false;
        await _enqueueApply();
      } catch (e) {
        debugPrint('[tray] init failed: $e');
        await _rollbackAfterInitFailure();
      }
    });
  }

  /// Safe dispose. No-op if not initialized or already disposed.
  Future<void> dispose() {
    return _enqueueLifecycle(() async {
      if (!_initialized || _disposed) return;
      _cancelPendingUpdate();
      _lastMenuSignature = '';
      _lastTooltip = '';
      _quitRequested = false;
      _lastStatus = const TrayStatus(mode: TrayStatusMode.idle);
      _autoCompressionToggleInFlight = false;
      _autoCompressionToggleOwner = null;
      _setAutoCompressionEnabled = null;
      try {
        await _updateQueue;
      } catch (_) {}

      try {
        _trayPlatform.removeListener(this);
      } catch (_) {}

      try {
        await _trayPlatform.destroy();
      } catch (e) {
        debugPrint('[tray] dispose destroy failed: $e');
      }

      // Clean up temp icon file.
      await _iconCache.deleteCachedFile();

      _initialized = false;
      _disposed = true;
    });
  }

  /// Resets all singleton state without calling platform APIs.
  /// For test isolation only — serializes singleton-mutating tests.
  @visibleForTesting
  void resetForTest() {
    _cancelPendingUpdate();
    _lastMenuSignature = '';
    _lastTooltip = '';
    _quitRequested = false;
    _lastStatus = const TrayStatus(mode: TrayStatusMode.idle);
    _initialized = false;
    _disposed = false;
    minimizeToTray = true;
    _iconCache = _TrayIconCache();
    _trayPlatform = const _DefaultTrayPlatformAdapter();
    _windowPlatform = const _DefaultWindowPlatformAdapter();
    _debounceDuration = const Duration(milliseconds: 400);
    _lifecycleQueue = Future<void>.value();
    _updateQueue = Future<void>.value();
    _setAutoCompressionEnabled = null;
    _autoCompressionToggleOwner = null;
    _autoCompressionToggleInFlight = false;
  }

  @visibleForTesting
  void configureForTest({
    TrayPlatformAdapter? trayPlatform,
    WindowPlatformAdapter? windowPlatform,
    Duration? debounceDuration,
    String? iconPathOverride,
    Future<void> Function(bool enabled)? setAutoCompressionEnabled,
  }) {
    _trayPlatform = trayPlatform ?? _trayPlatform;
    _windowPlatform = windowPlatform ?? _windowPlatform;
    _debounceDuration = debounceDuration ?? _debounceDuration;
    _iconCache.testIconPathOverride = iconPathOverride;
    _setAutoCompressionEnabled =
        setAutoCompressionEnabled ?? _setAutoCompressionEnabled;
    if (setAutoCompressionEnabled != null) {
      _autoCompressionToggleOwner = null;
    }
  }

  @visibleForTesting
  Future<void> flushPendingUpdateForTest() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _enqueueApply();
  }

  void registerAutoCompressionToggle({
    required Object owner,
    required Future<void> Function(bool enabled) setEnabled,
  }) {
    if (_setAutoCompressionEnabled != null &&
        identical(_autoCompressionToggleOwner, owner)) {
      return;
    }
    _autoCompressionToggleOwner = owner;
    _setAutoCompressionEnabled = setEnabled;
    if (!_initialized) {
      return;
    }
    _pendingStatus ??= _lastStatus;
    unawaited(_enqueueApply());
  }

  void unregisterAutoCompressionToggle(Object owner) {
    if (!identical(_autoCompressionToggleOwner, owner)) {
      return;
    }
    _autoCompressionToggleOwner = null;
    _setAutoCompressionEnabled = null;
    _autoCompressionToggleInFlight = false;
    if (!_initialized) {
      return;
    }
    _pendingStatus ??= _lastStatus;
    unawaited(_enqueueApply());
  }

  /// Coalesced status update on fixed tick.
  ///
  /// Updates that arrive within [_debounceDuration] are merged into the latest
  /// pending status and applied on the next tick.
  void update(TrayStatus status) {
    final latestStatus = _pendingStatus ?? _lastStatus;
    if (status == latestStatus) return;

    _pendingStatus = status;
    if (!_initialized) return;

    _scheduleApplyTick();
  }

  /// Explicit quit request from tray menu — bypasses minimize-to-tray.
  Future<void> requestQuit() async {
    _quitRequested = true;
    try {
      await _windowPlatform.close();
    } catch (e) {
      debugPrint('[tray] requestQuit close failed: $e');
    }
  }

  // -- TrayListener callbacks (fire-and-forget, no blocking work) ----------

  @override
  void onTrayIconMouseDown() {
    unawaited(_showAndFocusWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_trayPlatform.popUpContextMenu().catchError((Object _) {}));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showAndFocusWindow());
        return;
      case 'quit':
        unawaited(requestQuit());
        return;
      case 'toggle_auto':
        unawaited(_toggleAutoCompression());
        return;
      default:
        return;
    }
  }

  // -- Private helpers -----------------------------------------------------

  Future<void> _enqueueApply() {
    final next = _updateQueue.then((_) => _drainPendingUpdates());
    _updateQueue = next.catchError((Object _) {});
    return next;
  }

  void _scheduleApplyTick() {
    if (_debounceTimer != null || !_initialized) {
      return;
    }
    _debounceTimer = Timer(_debounceDuration, () {
      _debounceTimer = null;
      unawaited(
        _enqueueApply().whenComplete(() {
          if (_initialized && _pendingStatus != null) {
            _scheduleApplyTick();
          }
        }),
      );
    });
  }

  Future<void> _drainPendingUpdates() async {
    while (_initialized) {
      final status = _pendingStatus;
      if (status == null) {
        return;
      }
      _pendingStatus = null;
      _lastStatus = status;

      try {
        await _rebuildMenu(status);
      } catch (e) {
        debugPrint('[tray] menu rebuild failed: $e');
      }

      if (!_initialized) {
        return;
      }

      // If a newer status arrived while menu update was in flight, skip
      // stale tooltip writes and continue with the latest queued state.
      if (_pendingStatus != null) {
        continue;
      }

      await _updateTooltip(status);
    }
  }

  /// Builds a compact signature string from status to detect menu changes.
  /// Only calls setContextMenu when the signature differs from last time.
  /// Excludes progressPercent — tooltip carries per-percent updates;
  /// the context menu rebuilds on mode/game or automation-toggle changes.
  Future<void> _rebuildMenu(TrayStatus status) async {
    final sig = trayMenuSignature(
      status: status,
      hasToggleHandler: _setAutoCompressionEnabled != null,
      toggleInFlight: _autoCompressionToggleInFlight,
    );
    if (sig == _lastMenuSignature) return;

    final items = buildTrayMenuItems(
      status: status,
      hasToggleHandler: _setAutoCompressionEnabled != null,
      toggleInFlight: _autoCompressionToggleInFlight,
    );
    await _trayPlatform.setContextMenu(Menu(items: items));
    _lastMenuSignature = sig;
  }

  Future<void> _updateTooltip(TrayStatus status) async {
    final tooltip = trayTooltipForStatus(status);

    try {
      if (tooltip == _lastTooltip) {
        return;
      }
      await _trayPlatform.setToolTip(tooltip);
      _lastTooltip = tooltip;
    } catch (_) {}
  }

  Future<void> _showAndFocusWindow() async {
    try {
      await _windowPlatform.show();
      await _windowPlatform.focus();
    } catch (_) {}
  }

  Future<void> _toggleAutoCompression() async {
    final setEnabled = _setAutoCompressionEnabled;
    if (setEnabled == null || _autoCompressionToggleInFlight) {
      return;
    }

    final latestStatus = _pendingStatus ?? _lastStatus;
    final nextEnabled = !latestStatus.autoCompressionEnabled;

    _autoCompressionToggleInFlight = true;
    _pendingStatus ??= latestStatus;
    unawaited(_enqueueApply());
    try {
      await setEnabled(nextEnabled);
    } catch (e) {
      debugPrint('[tray] auto-compression toggle failed: $e');
    } finally {
      _autoCompressionToggleInFlight = false;
      _pendingStatus ??= _lastStatus;
      unawaited(_enqueueApply());
    }
  }

  Future<void> _enqueueLifecycle(Future<void> Function() op) {
    final next = _lifecycleQueue.then((_) => op());
    _lifecycleQueue = next.catchError((Object _) {});
    return next;
  }

  void _cancelPendingUpdate() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingStatus = null;
  }

  Future<void> _rollbackAfterInitFailure() async {
    try {
      _trayPlatform.removeListener(this);
    } catch (_) {}
    try {
      await _trayPlatform.destroy();
    } catch (_) {}
    await _iconCache.deleteCachedFile();
    _initialized = false;
    _disposed = false;
  }
}
